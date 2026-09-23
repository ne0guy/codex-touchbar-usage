import Foundation

public enum UsageFormatting {
    public static func clamp(_ value: Double, low: Double = 0, high: Double = 100) -> Double {
        max(low, min(high, value))
    }

    public static func remainingPercent(usedPercent: Double?) -> Double? {
        guard let usedPercent else { return nil }
        return clamp(100 - usedPercent)
    }

    public static func balanceLabel(usedPercent: Double?) -> String {
        percentLabel(remainingPercent(usedPercent: usedPercent))
    }

    public static func percentLabel(_ value: Double?) -> String {
        guard let value else { return "--%" }
        if abs(value - value.rounded()) < 0.05 {
            return "\(Int(value.rounded()))%"
        }
        return String(format: "%.1f%%", value)
    }

    public static func resetLabel(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "--/-- --:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    public static func resetCreditCountLabel(_ availableCount: Int?) -> String {
        guard let availableCount else { return "--" }
        return "\(max(0, availableCount))"
    }

    public static func windowLabel(_ window: LimitWindow?) -> String {
        guard let window else { return "--" }
        let normalizedName = window.name.lowercased()
        if normalizedName.contains("spark") || normalizedName.contains("bengalfox") {
            return "Spark"
        }
        guard let minutes = window.windowMinutes, minutes > 0 else { return "--" }
        if minutes == 10_080 { return "1w" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    public static func tokenCount(_ value: Int?) -> String {
        guard let value else { return "--" }
        if value >= 1_000_000_000 {
            let amount = Double(value) / 1_000_000_000
            return amount < 10 ? String(format: "%.1fB", amount) : String(format: "%.0fB", amount)
        }
        if value >= 1_000_000 {
            let amount = Double(value) / 1_000_000
            return amount < 100 ? String(format: "%.1fM", amount) : String(format: "%.0fM", amount)
        }
        if value >= 1_000 {
            let amount = Double(value) / 1_000
            return String(format: "%.1fK", amount)
        }
        return "\(value)"
    }

    public static func trackedWindows(_ snapshot: UsageSnapshot) -> (fiveHour: LimitWindow?, weekly: LimitWindow?) {
        let available = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        return (
            available.first { $0.windowMinutes == 300 },
            available.first { $0.windowMinutes == 10_080 }
        )
    }

    public static func cumulativeTokenCount(_ snapshot: UsageSnapshot) -> Int? {
        snapshot.cumulativeTokens ?? snapshot.totalTokens
    }

    public static func tokenRows(_ snapshot: UsageSnapshot) -> (String, String) {
        return (
            "Yesterday \(tokenCount(snapshot.yesterdayTokens))",
            "Lifetime \(tokenCount(cumulativeTokenCount(snapshot)))"
        )
    }
}
