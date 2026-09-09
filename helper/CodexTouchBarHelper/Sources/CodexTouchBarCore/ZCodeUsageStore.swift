import Foundation

public actor ZCodeUsageStore {
    private struct BackoffState {
        var failures = 0
        var nextAttemptAt: Date?

        func canAttempt(at date: Date, force: Bool) -> Bool {
            force || nextAttemptAt == nil || date >= nextAttemptAt!
        }

        mutating func recordFailure(at date: Date) {
            failures = min(failures + 1, 3)
            let delays: [TimeInterval] = [60, 120, 300]
            nextAttemptAt = date.addingTimeInterval(delays[max(0, failures - 1)])
        }

        mutating func recordSuccess() {
            failures = 0
            nextAttemptAt = nil
        }
    }

    private enum RemoteOutcome {
        case go(Result<ZCodeGoUsage, ZCodeClientError>)
        case glm(Result<ZCodeGLMUsage, ZCodeClientError>)
    }

    private let zcodeHome: URL
    private let cacheFile: URL
    private let statsStore: ZCodeTokenStatsStore
    private let goClient: ZCodeGoUsageClient
    private let glmClient: ZCodeGLMQuotaClient
    private var snapshot: ZCodeUsageSnapshot
    private var goBackoff = BackoffState()
    private var glmBackoff = BackoffState()

    public init(
        zcodeHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zcode"),
        cacheDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/touchbar-usage")
    ) {
        self.zcodeHome = zcodeHome
        self.cacheFile = cacheDirectory.appendingPathComponent("zcode-usage-cache.json")
        self.statsStore = ZCodeTokenStatsStore(
            zcodeHome: zcodeHome,
            cacheFile: cacheDirectory.appendingPathComponent("zcode-stats-cache.json")
        )
        self.goClient = ZCodeGoUsageClient(zcodeHome: zcodeHome)
        self.glmClient = ZCodeGLMQuotaClient(zcodeHome: zcodeHome)
        self.snapshot = Self.loadSnapshot(from: self.cacheFile)
    }

    public func refreshLocal() async -> ZCodeUsageSnapshot {
        guard !Task.isCancelled else { return snapshot }
        let now = Date()
        let result = statsStore.refresh(now: now)
        guard !Task.isCancelled else { return snapshot }

        snapshot.todayTokens = result.todayTokens
        snapshot.cumulativeTokens = result.cumulativeTokens
        snapshot.statsReady = result.statsReady
        if let provider = result.provider {
            snapshot.provider = provider
        } else if result.statsReady, result.todayTokens == nil, result.cumulativeTokens == nil {
            snapshot.provider = .unknown
        }
        if let error = result.error {
            snapshot.errors["stats"] = error
        } else if result.invalidRecordCount > 0 {
            snapshot.errors["stats"] = "ignored \(result.invalidRecordCount) invalid records"
        } else {
            snapshot.errors.removeValue(forKey: "stats")
        }
        snapshot.fetchedAt = Int(now.timeIntervalSince1970)
        persistSnapshot()
        return snapshot
    }

    public func refreshRemote(force: Bool = false) async -> ZCodeUsageSnapshot {
        guard !Task.isCancelled else { return snapshot }
        let now = Date()
        let shouldFetchGo = goBackoff.canAttempt(at: now, force: force)
        let shouldFetchGLM = glmBackoff.canAttempt(at: now, force: force)
        guard shouldFetchGo || shouldFetchGLM else { return snapshot }

        let goClient = self.goClient
        let glmClient = self.glmClient
        let outcomes = await withTaskGroup(of: RemoteOutcome.self, returning: [RemoteOutcome].self) { group in
            if shouldFetchGo {
                group.addTask {
                    .go(await goClient.fetchResult())
                }
            }
            if shouldFetchGLM {
                group.addTask {
                    .glm(await glmClient.fetchResult())
                }
            }

            var values: [RemoteOutcome] = []
            while let value = await group.next() {
                values.append(value)
            }
            return values
        }

        guard !Task.isCancelled else { return snapshot }
        for outcome in outcomes {
            switch outcome {
            case .go(let result):
                applyGo(result, at: now)
            case .glm(let result):
                applyGLM(result, at: now)
            }
        }
        guard !Task.isCancelled else { return snapshot }
        snapshot.fetchedAt = Int(now.timeIntervalSince1970)
        persistSnapshot()
        return snapshot
    }

    public func cachedSnapshot() -> ZCodeUsageSnapshot {
        snapshot
    }

    private func applyGo(_ result: Result<ZCodeGoUsage, ZCodeClientError>, at date: Date) {
        switch result {
        case .success(let usage):
            goBackoff.recordSuccess()
            snapshot.goRolling = usage.rolling
            snapshot.goWeekly = usage.weekly
            snapshot.goMonthly = usage.monthly
            snapshot.errors.removeValue(forKey: "go")
        case .failure(let error):
            goBackoff.recordFailure(at: date)
            snapshot.goRolling = nil
            snapshot.goWeekly = nil
            snapshot.goMonthly = nil
            snapshot.errors["go"] = error.safeDescription
        }
    }

    private func applyGLM(_ result: Result<ZCodeGLMUsage, ZCodeClientError>, at date: Date) {
        switch result {
        case .success(let usage):
            glmBackoff.recordSuccess()
            snapshot.glmPrimary = usage.primary
            snapshot.glmWeekly = usage.weekly
            snapshot.errors.removeValue(forKey: "glm")
        case .failure(let error):
            glmBackoff.recordFailure(at: date)
            snapshot.glmPrimary = nil
            snapshot.glmWeekly = nil
            snapshot.errors["glm"] = error.safeDescription
        }
    }

    private func persistSnapshot() {
        guard let data = try? JSONEncoder.zcodeEncoder.encode(snapshot) else { return }
        try? ZCodeAtomicFile.write(data, to: cacheFile)
    }

    private static func loadSnapshot(from url: URL) -> ZCodeUsageSnapshot {
        guard
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(ZCodeUsageSnapshot.self, from: data)
        else {
            return .placeholder
        }
        return snapshot
    }
}
