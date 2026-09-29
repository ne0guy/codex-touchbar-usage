import Foundation

public struct TouchBarPreferences: Codable, Equatable {
    public enum Accent: String, Codable, CaseIterable { case green, blue, amber }
    public enum BarSize: String, Codable, CaseIterable { case standard, compact }

    public var fiveHour = true
    public var weekly = true
    public var bars = true
    public var percentages = true
    public var resetTimes = true
    public var yesterdayTokens = true
    public var lifetimeTokens = true
    public var showUsed = false
    public var accent: Accent = .green
    public var barSize: BarSize = .standard

    public init() {}
    public static let defaultsKey = "touchBarPreferences.v1"

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    public func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    public var hasWindows: Bool { fiveHour || weekly }
    public var segmentWidth: Double { barSize == .compact ? 12 : 21 }
    public var barColumnWidth: Double { barSize == .compact ? 182 : 272 }
    public var tokenX: Double {
        guard hasWindows else { return 8 }
        return 40 + (bars ? barColumnWidth : 0) + (percentages ? 58 : 0) + (resetTimes ? 98 : 0)
    }
    public var contentWidth: Double {
        tokenX + (yesterdayTokens || lifetimeTokens ? 150 : 0) + 18
    }
}
