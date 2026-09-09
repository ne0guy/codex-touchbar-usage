import Foundation

#if !ZCODE_STANDALONE
@testable import CodexTouchBarCore
#endif

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if ZCODE_TESTING
private final class ZCodeTestURLProtocol: URLProtocol {
    static var handler: ((URLRequest, Int) -> (Int, Data))?
    static var delay: TimeInterval = 0
    private static var requestCounts: [String: Int] = [:]
    private static var authorizationHeaders: [String] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        requestCounts = [:]
        authorizationHeaders = []
        delay = 0
        handler = nil
        lock.unlock()
    }

    static func count(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCounts[url.absoluteString] ?? 0
    }

    static var seenAuthorizationHeaders: [String] {
        lock.lock()
        defer { lock.unlock() }
        return authorizationHeaders
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let delay = Self.delay
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.finishLoading()
            }
        } else {
            finishLoading()
        }
    }

    override func stopLoading() {}

    private func finishLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        let count = (Self.requestCounts[url.absoluteString] ?? 0) + 1
        Self.requestCounts[url.absoluteString] = count
        if let authorization = request.value(forHTTPHeaderField: "Authorization") {
            Self.authorizationHeaders.append(authorization)
        }
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else { return }
        let (status, data) = handler(request, count)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
#endif

enum ZCodeStandaloneChecks {
    enum Failure: Error, CustomStringConvertible {
        case assertion(String)

        var description: String {
            switch self {
            case .assertion(let message):
                return message
            }
        }
    }

    static func run() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zcode-core-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var assertions = 0
        assertions += try testQuotaParsers()
        assertions += try testCredentialDiscovery(root: root)
        assertions += try testChunkedLines(root: root)
        assertions += try testIncrementalCacheAndMidnight(root: root)
        assertions += try testReplacementAndSourceSelection(root: root)
        assertions += try testDirectoryAvailability(root: root)
#if ZCODE_TESTING
        assertions += try await testCancellationWithoutRequestID(root: root)
        assertions += try await testTransportCancellationAndBackoff(root: root)
#endif
        print("ZCode standalone checks: PASS (\(assertions) assertions)")
    }

    private static func testQuotaParsers() throws -> Int {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw Failure.assertion(message) }
        }

        let goData = try jsonData([
            "usage": [
                "rolling": ["status": "ok", "percent": 0, "resetsAt": "2026-09-08T08:25:39.871Z"],
                "weekly": ["status": "ok", "percent": 0, "resetsAt": "2026-09-14T00:00:00.871Z"],
                "monthly": ["status": "ok", "percent": 0, "resetsAt": "2026-09-10T01:34:27.871Z"]
            ]
        ])
        let go = try ZCodeGoUsageParser.parse(goData)
        try check(go.rolling?.usedPercent == 0, "Go zero percentage must remain valid")
        try check(go.rolling?.resetsAt == 1_788_855_939, "Go fractional ISO date was not parsed")

        let glmData = try jsonData([
            "code": 200,
            "success": true,
            "data": [
                "limits": [
                    [
                        "type": "TOKENS_LIMIT",
                        "unit": 3,
                        "number": 5,
                        "percentage": 0,
                        "nextResetTime": 1_788_929_097_592
                    ],
                    [
                        "type": "CREDIT_LIMIT",
                        "unit": 6,
                        "percentage": 0,
                        "nextResetTime": 1_789_106_366_699
                    ]
                ]
            ]
        ])
        let glm = try ZCodeGLMQuotaParser.parse(glmData)
        try check(glm.primary?.usedPercent == 0, "GLM TOKENS_LIMIT 5h zero percentage must remain valid")
        try check(glm.primary?.resetsAt == 1_788_929_097, "GLM millisecond reset was not converted")
        try check(glm.weekly?.usedPercent == 0, "GLM CREDIT_LIMIT week must accept missing number")
        try check(glm.weekly?.resetsAt == 1_789_106_366, "GLM week millisecond reset was not converted")
        try check(zcodePercent(101) == nil && zcodePercent(-1) == nil, "Invalid percentages must be unavailable")
        return assertions
    }

    private static func testCredentialDiscovery(root: URL) throws -> Int {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw Failure.assertion(message) }
        }

        let home = try makeZCodeHome(root: root, name: "credentials")
        try writeJSON([
            "provider": [
                "dynamic-go-provider": [
                    "name": "Configured Go alias",
                    "options": [
                        "baseURL": "https://opencode.ai/zen/go/v1/",
                        "apiKey": "go-config-key"
                    ]
                ],
                "builtin:bigmodel-coding-plan": [
                    "options": ["apiKey": "glm-config-key"]
                ],
                "zen-provider": [
                    "name": "OpenCode Zen",
                    "options": [
                        "baseURL": "https://opencode.ai/zen/v1",
                        "apiKey": "wrong-zen-key"
                    ]
                ]
            ]
        ], to: ZCodeCredentialReader(zcodeHome: home).configURL)

        let discovered = ZCodeCredentialReader(zcodeHome: home).discover()
        try check(discovered.goKey == "go-config-key", "Go key was not discovered from exact base URL")
        try check(discovered.glmKey == "glm-config-key", "GLM key was not discovered from exact builtin provider")
        try check(discovered.goProviderIDs.contains("dynamic-go-provider"), "Dynamic Go provider ID was not retained")
        try check(!discovered.goProviderIDs.contains("zen-provider"), "Arbitrary Zen provider was accepted")

        let fallbackHome = try makeZCodeHome(root: root, name: "credential-fallback")
        let fallbackURL = root.appendingPathComponent("fallback-auth.json")
        try writeJSON(["opencode-go": ["key": "go-fallback-key"]], to: fallbackURL)
        let fallback = ZCodeCredentialReader(zcodeHome: fallbackHome, fallbackAuthURL: fallbackURL).discover()
        try check(fallback.goKey == "go-fallback-key", "Go fallback auth key was not discovered")
        return assertions
    }

    private static func testChunkedLines(root: URL) throws -> Int {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw Failure.assertion(message) }
        }

        let home = try makeZCodeHome(root: root, name: "chunked")
        let cache = root.appendingPathComponent("chunked-cache")
        let file = home.appendingPathComponent("cli/rollout/model-io-sess_large.jsonl")
        var largeRecord = request(
            date: "2026-09-09T00:00:00.000Z",
            providerID: "builtin:bigmodel-coding-plan",
            totalTokens: 23,
            requestID: "large-record"
        )
        largeRecord["padding"] = String(repeating: "x", count: 2 * 1024 * 1024 + 128)
        try jsonLine(largeRecord).write(to: file, options: .atomic)

        let calendar = utcCalendar()
        let day = try date("2026-09-09T12:00:00.000Z")
        let store = ZCodeTokenStatsStore(zcodeHome: home, cacheFile: cache)
        let first = store.refresh(maxBytes: 2 * 1024 * 1024, now: day, calendar: calendar)
        try check(first.cumulativeTokens == nil, "Oversized line was parsed before its newline arrived")
        try check(!first.statsReady, "Unread oversized line must keep scan incomplete")

        let second = store.refresh(maxBytes: 2 * 1024 * 1024, now: day, calendar: calendar)
        try check(second.cumulativeTokens == 23, "Cross-chunk oversized line was not counted")
        try check(second.statsReady, "Completed historical scan was not ready")

        let partial = try jsonLine(request(
            date: "2026-09-09T00:01:00.000Z",
            providerID: "builtin:bigmodel-coding-plan",
            totalTokens: 7,
            requestID: "partial-record"
        )).dropLast()
        try append(Data(partial), to: file)
        let half = store.refresh(maxBytes: 1024, now: day, calendar: calendar)
        try check(half.cumulativeTokens == 23, "EOF partial line changed the tally")
        try check(half.statsReady, "EOF partial line must be caught-up")
        try append(Data([10]), to: file)
        let completed = store.refresh(maxBytes: 1024, now: day, calendar: calendar)
        try check(completed.cumulativeTokens == 30, "Partial line was not counted after completion")
        return assertions
    }

    private static func testIncrementalCacheAndMidnight(root: URL) throws -> Int {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw Failure.assertion(message) }
        }

        let home = try makeZCodeHome(root: root, name: "incremental")
        let cache = root.appendingPathComponent("incremental-cache")
        let file = home.appendingPathComponent("cli/rollout/model-io-sess_incremental.jsonl")
        let records = [
            request(date: "2026-09-08T23:59:00.000Z", providerID: "builtin:bigmodel-coding-plan", totalTokens: 5, requestID: "r1"),
            request(date: "2026-09-09T00:01:00.000Z", providerID: "builtin:bigmodel-coding-plan", totalTokens: 7, requestID: "r2"),
            request(date: "2026-09-10T00:01:00.000Z", providerID: "builtin:bigmodel-coding-plan", totalTokens: 11, requestID: "r3")
        ]
        try writeLines(records, to: file)
        let calendar = utcCalendar()
        let dayTwo = try date("2026-09-09T12:00:00.000Z")
        let incremental = ZCodeTokenStatsStore(zcodeHome: home, cacheFile: cache)
        var incrementalResult = incremental.refresh(maxBytes: 80, now: dayTwo, calendar: calendar)
        for _ in 0..<100 where !incrementalResult.statsReady {
            incrementalResult = incremental.refresh(maxBytes: 80, now: dayTwo, calendar: calendar)
        }
        try check(incrementalResult.statsReady, "Incremental scanner did not reach all files")
        try check(incrementalResult.todayTokens == 7, "Local-day token tally is wrong")
        try check(incrementalResult.cumulativeTokens == 23, "Incremental cumulative tally is wrong")

        let full = ZCodeTokenStatsStore(zcodeHome: home, cacheFile: root.appendingPathComponent("full-cache"))
        let fullResult = full.refresh(maxBytes: 10 * 1024 * 1024, now: dayTwo, calendar: calendar)
        try check(incrementalResult.todayTokens == fullResult.todayTokens, "Incremental and full daily tallies differ")
        try check(incrementalResult.cumulativeTokens == fullResult.cumulativeTokens, "Incremental and full cumulative tallies differ")

        let reloaded = ZCodeTokenStatsStore(zcodeHome: home, cacheFile: cache)
        let reloadedResult = reloaded.refresh(maxBytes: 80, now: dayTwo, calendar: calendar)
        try check(reloadedResult.cumulativeTokens == 23, "Stats cache reload changed cumulative tally")
        try check(reloadedResult.statsReady, "Stats cache reload lost ready state")

        try append(jsonLine(records[0]), to: file)
        let duplicate = reloaded.refresh(maxBytes: 1024, now: dayTwo, calendar: calendar)
        try check(duplicate.cumulativeTokens == 23, "Repeated request ID was counted twice")
        let afterMidnight = reloaded.refresh(
            maxBytes: 80,
            now: try date("2026-09-10T12:00:00.000Z"),
            calendar: calendar
        )
        try check(afterMidnight.todayTokens == 11, "Day rollover did not recalculate today's tokens")
        return assertions
    }

    private static func testReplacementAndSourceSelection(root: URL) throws -> Int {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw Failure.assertion(message) }
        }

        let replacementHome = try makeZCodeHome(root: root, name: "replacement")
        let replacementCache = root.appendingPathComponent("replacement-cache")
        let replacementFile = replacementHome.appendingPathComponent("cli/rollout/model-io-sess_replace.jsonl")
        try jsonLine(request(
            date: "2026-09-09T01:00:00.000Z",
            providerID: "builtin:bigmodel-coding-plan",
            totalTokens: 5,
            requestID: "replace-id"
        )).write(to: replacementFile, options: .atomic)
        try setModificationDate(Date(timeIntervalSince1970: 1_800_000_000), for: replacementFile)
        let calendar = utcCalendar()
        let now = try date("2026-09-09T12:00:00.000Z")
        let replacementStore = ZCodeTokenStatsStore(zcodeHome: replacementHome, cacheFile: replacementCache)
        _ = replacementStore.refresh(maxBytes: 10_000, now: now, calendar: calendar)
        try jsonLine(request(
            date: "2026-09-09T01:00:00.000Z",
            providerID: "builtin:bigmodel-coding-plan",
            totalTokens: 9,
            requestID: "replace-id"
        )).write(to: replacementFile, options: .atomic)
        try setModificationDate(Date(timeIntervalSince1970: 1_800_000_001), for: replacementFile)
        let replaced = replacementStore.refresh(maxBytes: 10_000, now: now, calendar: calendar)
        try check(replaced.cumulativeTokens == 9, "Same-size file replacement was not recounted")

        let sourceHome = try makeZCodeHome(root: root, name: "source-selection")
        try writeJSON([
            "provider": [
                "runtime-go-provider": [
                    "name": "Configured runtime",
                    "options": [
                        "baseURL": "https://opencode.ai/zen/go/v1",
                        "apiKey": "go-test-key"
                    ]
                ]
            ]
        ], to: ZCodeCredentialReader(zcodeHome: sourceHome).configURL)
        let sourceCache = root.appendingPathComponent("source-cache")
        let glmFile = sourceHome.appendingPathComponent("cli/rollout/model-io-sess_a.jsonl")
        let goFile = sourceHome.appendingPathComponent("cli/rollout/model-io-sess_b.jsonl")
        try writeLines([
            request(date: "2026-09-09T02:00:00.000Z", providerID: "builtin:bigmodel-coding-plan", totalTokens: 3, requestID: "glm-old")
        ], to: glmFile)
        try writeLines([
            request(date: "2026-09-09T03:00:00.000Z", providerID: "runtime-go-provider", totalTokens: 4, requestID: "go-new")
        ], to: goFile)
        let sourceStore = ZCodeTokenStatsStore(zcodeHome: sourceHome, cacheFile: sourceCache)
        let goResult = sourceStore.refresh(maxBytes: 10_000, now: now, calendar: calendar)
        try check(goResult.provider == .go, "Newest valid Go request did not select Go")
        try append(jsonLine(request(
            date: "2026-09-09T04:00:00.000Z",
            providerID: "builtin:bigmodel-coding-plan",
            totalTokens: 6,
            requestID: "glm-new"
        )), to: glmFile)
        let glmResult = sourceStore.refresh(maxBytes: 10_000, now: now, calendar: calendar)
        try check(glmResult.provider == .glm, "Newest valid GLM request did not select GLM")
        return assertions
    }

    private static func testDirectoryAvailability(root: URL) throws -> Int {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw Failure.assertion(message) }
        }

        let emptyHome = try makeZCodeHome(root: root, name: "empty-rollout")
        let empty = ZCodeTokenStatsStore(
            zcodeHome: emptyHome,
            cacheFile: root.appendingPathComponent("empty-rollout-cache")
        )
        let calendar = utcCalendar()
        let now = try date("2026-09-09T12:00:00.000Z")
        let emptyResult = empty.refresh(now: now, calendar: calendar)
        try check(emptyResult.todayTokens == 0, "Readable empty rollout directory must report today's zero")
        try check(emptyResult.cumulativeTokens == 0, "Readable empty rollout directory must report cumulative zero")
        try check(emptyResult.statsReady, "Readable empty rollout directory must be ready")

        let badHome = try makeZCodeHome(root: root, name: "bad-rollout")
        let badFile = badHome.appendingPathComponent("cli/rollout/model-io-sess_bad.jsonl")
        try Data("not-json\n".utf8).write(to: badFile, options: .atomic)
        let bad = ZCodeTokenStatsStore(
            zcodeHome: badHome,
            cacheFile: root.appendingPathComponent("bad-rollout-cache")
        )
        let badResult = bad.refresh(now: now, calendar: calendar)
        try check(badResult.todayTokens == nil && badResult.cumulativeTokens == nil, "Only bad records must remain unavailable")
        try check(badResult.statsReady, "Only bad records should still finish scanning")

        let inaccessibleHome = try makeZCodeHome(root: root, name: "inaccessible-rollout")
        let inaccessibleDirectory = inaccessibleHome.appendingPathComponent("cli/rollout")
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o000)],
            ofItemAtPath: inaccessibleDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: inaccessibleDirectory.path
            )
        }
        let inaccessible = ZCodeTokenStatsStore(
            zcodeHome: inaccessibleHome,
            cacheFile: root.appendingPathComponent("inaccessible-rollout-cache")
        )
        let inaccessibleResult = inaccessible.refresh(now: now, calendar: calendar)
        try check(inaccessibleResult.todayTokens == nil && inaccessibleResult.cumulativeTokens == nil, "Unreadable rollout directory must remain unavailable")
        try check(inaccessibleResult.statsReady, "Unreadable rollout directory must not look like an endless initial scan")
        try check(inaccessibleResult.error == "rollout directory unreadable", "Unreadable rollout error must be explicit")
        return assertions
    }

#if ZCODE_TESTING
    private static func testCancellationWithoutRequestID(root: URL) async throws -> Int {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw Failure.assertion(message) }
        }

        let home = try makeZCodeHome(root: root, name: "cancel-no-request-id")
        let file = home.appendingPathComponent("cli/rollout/model-io-sess_cancel.jsonl")
        try writeLines([
            request(date: "2026-09-09T06:00:00.000Z", providerID: "builtin:bigmodel-coding-plan", totalTokens: 3),
            request(date: "2026-09-09T06:01:00.000Z", providerID: "builtin:bigmodel-coding-plan", totalTokens: 4)
        ], to: file)
        let store = ZCodeTokenStatsStore(
            zcodeHome: home,
            cacheFile: root.appendingPathComponent("cancel-no-request-id-cache")
        )
        ZCodeTokenStatsStore.testingCancelAfterCompleteLines = 1
        defer { ZCodeTokenStatsStore.testingCancelAfterCompleteLines = nil }
        let canceled = Task {
            store.refresh(maxBytes: 10_000, now: try! date("2026-09-09T12:00:00.000Z"), calendar: utcCalendar())
        }
        let first = await canceled.value
        try check(first.cumulativeTokens == 3, "Canceled scan did not retain the first parsed record")
        let resumed = store.refresh(
            maxBytes: 10_000,
            now: try date("2026-09-09T12:00:00.000Z"),
            calendar: utcCalendar()
        )
        try check(resumed.cumulativeTokens == 7, "Canceled scan duplicated a request without requestId")
        return assertions
    }

    private static func testTransportCancellationAndBackoff(root: URL) async throws -> Int {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw Failure.assertion(message) }
        }

        let home = try makeZCodeHome(root: root, name: "transport")
        try writeJSON([
            "provider": [
                "runtime-go-provider": [
                    "name": "OpenCode Go",
                    "options": [
                        "baseURL": "https://opencode.ai/zen/go/v1",
                        "apiKey": "go-key-one"
                    ]
                ],
                "builtin:bigmodel-coding-plan": ["options": ["apiKey": "glm-key"]]
            ]
        ], to: ZCodeCredentialReader(zcodeHome: home).configURL)

        let goURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!
        let glmURL = URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
        ZCodeTestURLProtocol.reset()
        ZCodeTestURLProtocol.handler = { request, count in
            if request.url == goURL {
                let body: [String: Any] = [
                    "usage": [
                        "rolling": ["status": "ok", "percent": count, "resetsAt": "2026-09-09T05:00:00.000Z"],
                        "weekly": ["status": "ok", "percent": 0, "resetsAt": "2026-09-14T00:00:00.000Z"],
                        "monthly": ["status": "ok", "percent": 1, "resetsAt": "2026-10-01T00:00:00.000Z"]
                    ]
                ]
                return (200, (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
            }
            return (401, Data("{}".utf8))
        }
        ZCodeHTTP.testingProtocolClasses = [ZCodeTestURLProtocol.self]
        let store = ZCodeUsageStore(zcodeHome: home, cacheDirectory: root.appendingPathComponent("transport-cache"))
        let first = await store.refreshRemote()
        try check(first.goRolling?.usedPercent == 1, "Injected Go transport did not update on first request")
        try check(first.errors["glm"] == "HTTP status 401", "GLM failure was not isolated")

        try writeJSON([
            "provider": [
                "runtime-go-provider": [
                    "name": "OpenCode Go",
                    "options": [
                        "baseURL": "https://opencode.ai/zen/go/v1",
                        "apiKey": "go-key-two"
                    ]
                ],
                "builtin:bigmodel-coding-plan": ["options": ["apiKey": "glm-key"]]
            ]
        ], to: ZCodeCredentialReader(zcodeHome: home).configURL)
        let second = await store.refreshRemote()
        try check(second.goRolling?.usedPercent == 2, "Healthy Go source was blocked by GLM backoff")
        try check(ZCodeTestURLProtocol.count(for: goURL) == 2, "Go source was not retried independently")
        try check(ZCodeTestURLProtocol.count(for: glmURL) == 1, "GLM failure backoff did not suppress immediate retry")
        try check(ZCodeTestURLProtocol.seenAuthorizationHeaders.contains("Bearer go-key-two"), "API key was not reread per attempt")

        ZCodeTestURLProtocol.reset()
        ZCodeTestURLProtocol.delay = 1
        ZCodeTestURLProtocol.handler = { _, _ in (200, Data("{}".utf8)) }
        let cancellationTask = Task { () -> String in
            do {
                _ = try await ZCodeHTTP.get(url: goURL, apiKey: "temporary-test-key")
                return "success"
            } catch let error as ZCodeClientError {
                return error.safeDescription
            } catch {
                return "other error"
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        cancellationTask.cancel()
        let cancellationResult = await cancellationTask.value
        try check(cancellationResult == "request cancelled", "URLSession cancellation was not preserved")
        ZCodeHTTP.testingProtocolClasses = nil
        ZCodeTestURLProtocol.reset()
        return assertions
    }
#endif

    private static func makeZCodeHome(root: URL, name: String) throws -> URL {
        let home = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("cli/rollout"),
            withIntermediateDirectories: true
        )
        return home
    }

    private static func request(
        date: String,
        providerID: String,
        totalTokens: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        requestID: String? = nil
    ) -> [String: Any] {
        var usage: [String: Any] = [:]
        if let totalTokens {
            usage["totalTokens"] = totalTokens
        } else {
            usage["inputTokens"] = inputTokens ?? 0
            usage["outputTokens"] = outputTokens ?? 0
        }
        var value: [String: Any] = [
            "completedAt": date,
            "model": ["providerId": providerID, "modelId": "test-model"],
            "response": ["usage": usage],
            "sessionId": "test-session",
            "turnId": "test-turn"
        ]
        if let requestID {
            value["requestId"] = requestID
        }
        return value
    }

    private static func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private static func jsonLine(_ value: [String: Any]) throws -> Data {
        var data = try jsonData(value)
        data.append(10)
        return data
    }

    private static func writeJSON(_ value: Any, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jsonData(value).write(to: url, options: .atomic)
    }

    private static func writeLines(_ values: [[String: Any]], to url: URL) throws {
        var data = Data()
        for value in values {
            data.append(try jsonLine(value))
        }
        try data.write(to: url, options: .atomic)
    }

    private static func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private static func date(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) {
            return value
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard let value = formatter.date(from: text) else {
            throw Failure.assertion("test date could not be parsed")
        }
        return value
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}

#if ZCODE_STANDALONE
@main
struct ZCodeStandaloneMain {
    static func main() async throws {
        try await ZCodeStandaloneChecks.run()
    }
}
#endif
