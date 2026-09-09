import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ZCodeGoUsage {
    let rolling: ZCodeQuota?
    let weekly: ZCodeQuota?
    let monthly: ZCodeQuota?
}

struct ZCodeGLMUsage {
    let primary: ZCodeQuota?
    let weekly: ZCodeQuota?
}

enum ZCodeClientError: Error {
    case missingAPIKey
    case httpStatus(Int)
    case invalidResponse(String)
    case networkTimeout
    case cancelled
    case networkFailure

    var safeDescription: String {
        switch self {
        case .missingAPIKey:
            return "API key unavailable"
        case .httpStatus(let status):
            return "HTTP status \(status)"
        case .invalidResponse(let source):
            return "invalid \(source) response"
        case .networkTimeout:
            return "network timeout"
        case .cancelled:
            return "request cancelled"
        case .networkFailure:
            return "network request failed"
        }
    }
}

private final class ZCodeRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum ZCodeHTTP {
    static let userAgent = "codex-touchbar-usage/zcode-usage"

#if ZCODE_TESTING
    static var testingProtocolClasses: [AnyClass]?
#endif

    static func get(url: URL, apiKey: String) async throws -> Data {
        try Task.checkCancellation()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
#if ZCODE_TESTING
        configuration.protocolClasses = testingProtocolClasses ?? configuration.protocolClasses
#endif
        let delegate = ZCodeRedirectRejectingDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw ZCodeClientError.networkFailure
            }
            guard response.statusCode == 200 else {
                throw ZCodeClientError.httpStatus(response.statusCode)
            }
            return data
        } catch let error as ZCodeClientError {
            throw error
        } catch is CancellationError {
            throw ZCodeClientError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw ZCodeClientError.networkTimeout
        } catch let error as URLError where error.code == .cancelled {
            throw ZCodeClientError.cancelled
        } catch {
            throw ZCodeClientError.networkFailure
        }
    }
}

final class ZCodeGoUsageClient {
    private let credentialReader: ZCodeCredentialReader
    private let endpoint = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    init(zcodeHome: URL) {
        credentialReader = ZCodeCredentialReader(zcodeHome: zcodeHome)
    }

    func fetch() async throws -> ZCodeGoUsage {
        try Task.checkCancellation()
        guard let key = credentialReader.discover().goKey else {
            throw ZCodeClientError.missingAPIKey
        }
        let data = try await ZCodeHTTP.get(url: endpoint, apiKey: key)
        try Task.checkCancellation()
        return try ZCodeGoUsageParser.parse(data)
    }

    func fetchResult() async -> Result<ZCodeGoUsage, ZCodeClientError> {
        do {
            return .success(try await fetch())
        } catch let error as ZCodeClientError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.networkFailure)
        }
    }
}

final class ZCodeGLMQuotaClient {
    private let credentialReader: ZCodeCredentialReader
    private let endpoint = URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!

    init(zcodeHome: URL) {
        credentialReader = ZCodeCredentialReader(zcodeHome: zcodeHome)
    }

    func fetch() async throws -> ZCodeGLMUsage {
        try Task.checkCancellation()
        guard let key = credentialReader.discover().glmKey else {
            throw ZCodeClientError.missingAPIKey
        }
        let data = try await ZCodeHTTP.get(url: endpoint, apiKey: key)
        try Task.checkCancellation()
        return try ZCodeGLMQuotaParser.parse(data)
    }

    func fetchResult() async -> Result<ZCodeGLMUsage, ZCodeClientError> {
        do {
            return .success(try await fetch())
        } catch let error as ZCodeClientError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.networkFailure)
        }
    }
}

enum ZCodeGoUsageParser {
    static func parse(_ data: Data) throws -> ZCodeGoUsage {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let usage = root["usage"] as? [String: Any]
        else {
            throw ZCodeClientError.invalidResponse("Go usage")
        }

        return ZCodeGoUsage(
            rolling: parseQuota(usage["rolling"]),
            weekly: parseQuota(usage["weekly"]),
            monthly: parseQuota(usage["monthly"])
        )
    }

    private static func parseQuota(_ value: Any?) -> ZCodeQuota? {
        guard let object = value as? [String: Any] else { return nil }
        if let status = object["status"] as? String,
           status.lowercased() != "ok" {
            return ZCodeQuota()
        }
        return ZCodeQuota(
            usedPercent: zcodePercent(object["percent"] ?? object["percentage"]),
            resetsAt: zcodeISOSeconds(object["resetsAt"])
        )
    }
}

enum ZCodeGLMQuotaParser {
    static func parse(_ data: Data) throws -> ZCodeGLMUsage {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = zcodeInteger(root["code"]),
            code == 200,
            (root["success"] as? Bool) == true,
            let dataObject = root["data"] as? [String: Any],
            let limits = dataObject["limits"] as? [Any]
        else {
            throw ZCodeClientError.invalidResponse("GLM quota")
        }

        var primary: ZCodeQuota?
        var weekly: ZCodeQuota?
        for value in limits {
            guard let limit = value as? [String: Any] else { continue }
            guard
                let type = limit["type"] as? String,
                type == "TOKENS_LIMIT" || type == "CREDIT_LIMIT"
            else {
                continue
            }
            let unit = zcodeInteger(limit["unit"])
            let number = zcodeInteger(limit["number"])
            let quota = ZCodeQuota(
                usedPercent: zcodePercent(limit["percentage"]),
                resetsAt: zcodeMillisSeconds(limit["nextResetTime"])
            )
            if unit == 3, number == 5 {
                primary = quota
            } else if unit == 6 {
                weekly = quota
            }
        }

        return ZCodeGLMUsage(primary: primary, weekly: weekly)
    }
}

func zcodeInteger(_ value: Any?) -> Int64? {
    if let value = value as? Int {
        return Int64(value)
    }
    if let value = value as? Int64 {
        return value
    }
    if let value = value as? NSNumber {
        let doubleValue = value.doubleValue
        guard doubleValue.isFinite, doubleValue.rounded() == doubleValue else { return nil }
        guard doubleValue >= Double(Int64.min), doubleValue <= Double(Int64.max) else { return nil }
        return Int64(doubleValue)
    }
    if let value = value as? String {
        return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
}

func zcodeNonNegativeInteger(_ value: Any?) -> Int64? {
    guard let value = zcodeInteger(value), value >= 0 else { return nil }
    return value
}

func zcodePercent(_ value: Any?) -> Double? {
    let number: Double
    if let value = value as? Double {
        number = value
    } else if let value = value as? Float {
        number = Double(value)
    } else if let value = value as? NSNumber {
        number = value.doubleValue
    } else if let value = value as? String, let parsed = Double(value) {
        number = parsed
    } else {
        return nil
    }
    guard number.isFinite, number >= 0, number <= 100 else { return nil }
    return number
}

func zcodeISOSeconds(_ value: Any?) -> Int? {
    guard let text = value as? String, !text.isEmpty else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    guard let date = fractional.date(from: text) ?? plain.date(from: text) else { return nil }
    guard date.timeIntervalSince1970.isFinite else { return nil }
    return Int(date.timeIntervalSince1970)
}

func zcodeMillisSeconds(_ value: Any?) -> Int? {
    guard let milliseconds = zcodeInteger(value), milliseconds >= 0 else { return nil }
    let seconds = milliseconds / 1_000
    guard Int64(Int.min) <= seconds, seconds <= Int64(Int.max) else { return nil }
    return Int(seconds)
}
