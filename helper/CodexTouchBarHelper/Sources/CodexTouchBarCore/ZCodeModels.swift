import Foundation

public enum ZCodeProvider: String, Codable {
    case glm
    case go
    case unknown
}

public struct ZCodeQuota: Codable, Equatable {
    public var usedPercent: Double?
    public var resetsAt: Int?

    public init(usedPercent: Double? = nil, resetsAt: Int? = nil) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct ZCodeUsageSnapshot: Codable, Equatable {
    public var provider: ZCodeProvider
    public var glmPrimary: ZCodeQuota?
    public var glmWeekly: ZCodeQuota?
    public var goRolling: ZCodeQuota?
    public var goWeekly: ZCodeQuota?
    public var goMonthly: ZCodeQuota?
    public var todayTokens: Int?
    public var cumulativeTokens: Int?
    public var statsReady: Bool
    public var errors: [String: String]
    public var fetchedAt: Int

    public init(
        provider: ZCodeProvider,
        glmPrimary: ZCodeQuota? = nil,
        glmWeekly: ZCodeQuota? = nil,
        goRolling: ZCodeQuota? = nil,
        goWeekly: ZCodeQuota? = nil,
        goMonthly: ZCodeQuota? = nil,
        todayTokens: Int? = nil,
        cumulativeTokens: Int? = nil,
        statsReady: Bool = false,
        errors: [String: String] = [:],
        fetchedAt: Int
    ) {
        self.provider = provider
        self.glmPrimary = glmPrimary
        self.glmWeekly = glmWeekly
        self.goRolling = goRolling
        self.goWeekly = goWeekly
        self.goMonthly = goMonthly
        self.todayTokens = todayTokens
        self.cumulativeTokens = cumulativeTokens
        self.statsReady = statsReady
        self.errors = errors
        self.fetchedAt = fetchedAt
    }

    public static var placeholder: Self {
        Self(
            provider: .unknown,
            statsReady: false,
            fetchedAt: Int(Date().timeIntervalSince1970)
        )
    }
}
