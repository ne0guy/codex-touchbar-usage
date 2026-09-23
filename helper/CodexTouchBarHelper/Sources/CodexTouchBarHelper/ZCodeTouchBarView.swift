import AppKit
import CodexTouchBarCore

final class ZCodeTouchBarView: NSView {
    var snapshot = ZCodeUsageSnapshot.placeholder {
        didSet {
            if snapshot.provider != .unknown { lastKnownProvider = snapshot.provider }
            needsDisplay = true
        }
    }
    private var lastKnownProvider: ZCodeProvider = .glm
    private(set) var showsDetails = false
    private let titleFont = NSFontManager.shared.convert(
        NSFont.systemFont(ofSize: 14.5, weight: .semibold), toHaveTrait: .italicFontMask)
    private let labelFont = NSFont.systemFont(ofSize: 12.7, weight: .semibold)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.7, weight: .semibold)
    private let dateFont = NSFont.monospacedDigitSystemFont(ofSize: 11.2, weight: .medium)
    private let tokenFont = NSFont.systemFont(ofSize: 11.4, weight: .semibold)
    private let white = NSColor(calibratedWhite: 0.94, alpha: 1)
    private let muted = NSColor(calibratedWhite: 0.78, alpha: 0.96)
    private let green = NSColor(calibratedRed: 0.72, green: 1, blue: 0.38, alpha: 1)
    private let highlight = NSColor(calibratedRed: 0.91, green: 1, blue: 0.68, alpha: 0.88)
    private let warning = NSColor(calibratedRed: 1, green: 0.76, blue: 0.28, alpha: 1)
    private let danger = NSColor(calibratedRed: 1, green: 0.36, blue: 0.32, alpha: 1)

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 720, height: 30) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        let button = NSButton(frame: bounds)
        button.title = ""
        button.isTransparent = true
        button.isBordered = false
        button.autoresizingMask = [.width, .height]
        button.target = self
        button.action = #selector(toggleDetails)
        button.setAccessibilityLabel("ZCode usage details")
        addSubview(button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc func toggleDetails() {
        showsDetails.toggle()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        if showsDetails { drawDetails(); return }
        let isGo = lastKnownProvider == .go
        let isUnknown = snapshot.provider == .unknown
        let primary = isGo ? snapshot.goRolling : snapshot.glmPrimary
        let secondary = isGo ? snapshot.goMonthly : snapshot.glmWeekly
        text(isUnknown ? "ZCode" : (isGo ? "Go" : "GLM"),
             x: 8, y: 7, width: 64, font: titleFont)
        text("5h", x: 75, y: 0, width: 43, font: labelFont)
        text(isGo ? "1mo" : "1w", x: 75, y: 15, width: 43, font: labelFont)
        drawQuota(primary, y: 0)
        drawQuota(secondary, y: 15)
        text("Today " + token(snapshot.todayTokens), x: 552, y: 0, width: 150, font: tokenFont)
        let other = isGo ? "Go Wk " + balance(snapshot.goWeekly) : "Go 5h " + balance(snapshot.goRolling)
        text(other, x: 552, y: 15, width: 150, font: tokenFont, color: muted)
    }

    private func drawQuota(_ quota: ZCodeQuota?, y: CGFloat) {
        bar(quota?.usedPercent, y: y + 4.5)
        text(balance(quota), x: 396, y: y, width: 42, font: valueFont, alignment: .right)
        text(date(quota?.resetsAt), x: 454, y: y, width: 82, font: dateFont, color: muted)
    }

    private func drawDetails() {
        let windows: [(String, ZCodeQuota?)] = [
            ("Go 5h", snapshot.goRolling), ("Go Wk", snapshot.goWeekly),
            ("Go Mo", snapshot.goMonthly), ("GLM 5h", snapshot.glmPrimary),
            ("GLM Wk", snapshot.glmWeekly)
        ]
        for (index, entry) in windows.enumerated() {
            let x = CGFloat(8 + index * 105)
            text(entry.0 + " " + balance(entry.1), x: x, y: 0, width: 101, font: dateFont)
            text(date(entry.1?.resetsAt), x: x, y: 15, width: 101, font: dateFont, color: muted)
        }
        text("Today " + token(snapshot.todayTokens), x: 543, y: 0, width: 169, font: tokenFont)
        text("Lifetime " + token(snapshot.cumulativeTokens), x: 543, y: 15, width: 169, font: tokenFont)
    }

    private func token(_ count: Int?) -> String {
        snapshot.statsReady ? UsageFormatting.tokenCount(count) : "…"
    }
    private func balance(_ quota: ZCodeQuota?) -> String {
        UsageFormatting.balanceLabel(usedPercent: quota?.usedPercent)
    }
    private func date(_ value: Int?) -> String {
        guard let value, value > 0 else { return "" }
        return UsageFormatting.resetLabel(value)
    }
    private func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat,
                      font: NSFont, color: NSColor? = nil, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 17),
            withAttributes: [.font: font, .foregroundColor: color ?? white, .paragraphStyle: paragraph])
    }

    private func bar(_ used: Double?, y: CGFloat) {
        let remaining = UsageFormatting.remainingPercent(usedPercent: used) ?? 0
        let color = remaining <= 10 ? danger : (remaining <= 30 ? warning : green)
        for i in 0..<10 {
            let x = 124 + CGFloat(i) * 26.2
            let rect = NSRect(x: x, y: y, width: 21, height: 7.8)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 3.9, yRadius: 3.9)
            NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.15, alpha: 1).setFill()
            shape.fill()
            NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.23, alpha: 0.9).setStroke()
            shape.lineWidth = 0.8
            shape.stroke()
            let fraction = min(1, max(0, (remaining - Double(i) * 10) / 10))
            guard fraction > 0 else { continue }
            let fillWidth = max(1.2, 21 * fraction)
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            color.setFill()
            NSRect(x: x, y: y, width: fillWidth, height: 7.8).fill()
            highlight.withAlphaComponent(remaining > 30 ? 0.88 : 0.44).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 1.4, y: y + 1.1,
                width: max(0, fillWidth - 2.8), height: 7.8 * 0.34), xRadius: 1.326, yRadius: 1.326).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
