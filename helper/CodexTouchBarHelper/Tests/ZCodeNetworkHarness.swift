import Foundation

private final class UsageProtocol: URLProtocol {
    static let lock = NSLock()
    static var failGo = false
    static var delay: TimeInterval = 0
    static var goRequests = 0
    static var glmRequests = 0
    private var work: DispatchWorkItem?
    static func configure(failGo: Bool, delay: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        self.failGo = failGo
        self.delay = delay
    }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "opencode.ai" || request.url?.host == "open.bigmodel.cn"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let isGo = request.url?.host == "opencode.ai"
        if isGo { Self.goRequests += 1 } else { Self.glmRequests += 1 }
        let status = isGo && Self.failGo ? 401 : 200
        let delay = Self.delay
        Self.lock.unlock()
        precondition(request.value(forHTTPHeaderField: "User-Agent")?.contains("codex-touchbar-usage") == true)
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only")
        let body = isGo
            ? #"{"usage":{"rolling":{"status":"ok","percent":0,"resetsAt":"2026-09-10T01:02:03.123Z"},"weekly":{"status":"ok","percent":15},"monthly":{"status":"ok","percent":23}}}"#
            : #"{"code":200,"success":true,"data":{"limits":[{"type":"CREDIT_LIMIT","unit":3,"number":5,"percentage":27,"nextResetTime":1788929097592},{"type":"TOKENS_LIMIT","unit":6,"percentage":72}]}}"#
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(url: self.request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(body.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        self.work = work
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
    }
    override func stopLoading() { work?.cancel() }
}

@main
struct ZCodeNetworkHarness {
    static func main() async throws {
        ZCodeHTTP.testingProtocolClasses = [UsageProtocol.self]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zcode-network-\(UUID().uuidString)")
        let config = root.appendingPathComponent("v2/config.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let providers: [String: Any] = [
            "go-fixture": ["name": "OpenCode Go", "options": ["apiKey": "fixture-only", "baseURL": "https://opencode.ai/zen/go/v1"]],
            "builtin:bigmodel-coding-plan": ["options": ["apiKey": "fixture-only"]]
        ]
        try JSONSerialization.data(withJSONObject: ["provider": providers]).write(to: config)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ZCodeUsageStore(zcodeHome: root, cacheDirectory: root.appendingPathComponent("cache"))
        let first = await store.refreshRemote(force: true)
        precondition(first.goRolling?.usedPercent == 0, "zero quota must be accepted")
        precondition(first.glmPrimary?.usedPercent == 27)
        UsageProtocol.configure(failGo: true, delay: 0)
        let failed = await store.refreshRemote(force: true)
        precondition(failed.goRolling == nil && failed.errors["go"] != nil)
        precondition(failed.glmPrimary?.usedPercent == 27, "GLM must survive Go failure")
        let previousGo = UsageProtocol.goRequests
        let previousGLM = UsageProtocol.glmRequests
        _ = await store.refreshRemote()
        precondition(UsageProtocol.goRequests == previousGo, "failed Go must back off")
        precondition(UsageProtocol.glmRequests > previousGLM, "healthy GLM must still refresh")
        UsageProtocol.configure(failGo: false, delay: 1)
        let beforeCancellation = await store.cachedSnapshot()
        let task = Task { await store.refreshRemote(force: true) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        _ = await task.value
        let afterCancellation = await store.cachedSnapshot()
        precondition(beforeCancellation == afterCancellation, "cancelled response must not mutate snapshot")
        print("Mock HTTP: success, all-zero, independent failure/backoff and cancellation PASS")
    }
}
