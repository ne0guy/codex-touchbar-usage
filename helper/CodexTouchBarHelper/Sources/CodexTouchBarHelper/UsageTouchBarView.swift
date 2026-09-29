import AppKit
import CodexTouchBarCore

final class UsageTouchBarView: NSView {
    var preferences = TouchBarPreferences() {
        didSet { needsDisplay = true }
    }

    var snapshot: UsageSnapshot? = .placeholder {
        didSet {
            errorMessage = nil
            needsDisplay = true
        }
    }

    var errorMessage: String? {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 720, height: 30) }

    private let labelFont = NSFont.systemFont(ofSize: 12.7, weight: .semibold)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.7, weight: .semibold)
    private let smallMonoFont = NSFont.monospacedDigitSystemFont(ofSize: 11.2, weight: .medium)
    private let tokenFont = NSFont.systemFont(ofSize: 11.4, weight: .semibold)

    private let white = NSColor(calibratedWhite: 0.94, alpha: 1)
    private let muted = NSColor(calibratedWhite: 0.78, alpha: 0.96)
    private let emptyFill = NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.15, alpha: 1)
    private let emptyStroke = NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.23, alpha: 0.9)
    private let green = NSColor(calibratedRed: 0.72, green: 1.0, blue: 0.38, alpha: 1)
    private let greenTop = NSColor(calibratedRed: 0.91, green: 1.0, blue: 0.68, alpha: 0.92)
    private let warning = NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.28, alpha: 1)
    private let danger = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.32, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        alphaValue = 0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        let snapshot = snapshot ?? .placeholder
        let windows = UsageFormatting.trackedWindows(snapshot)
        let textHeight: CGFloat = 15
        var rows: [(String, LimitWindow?)] = []
        if preferences.fiveHour { rows.append(("5h", windows.fiveHour)) }
        if preferences.weekly { rows.append(("1w", windows.weekly)) }

        let barX: CGFloat = 40
        let percentX = barX + (preferences.bars ? CGFloat(preferences.barColumnWidth) : 0)
        let dateX = percentX + (preferences.percentages ? 58 : 0)
        let tokenX = CGFloat(preferences.tokenX)

        for (index, row) in rows.enumerated() {
            let y: CGFloat = rows.count == 1 ? 7.5 : CGFloat(index) * 15
            drawText(row.0, in: NSRect(x: 8, y: y, width: 24, height: textHeight), font: labelFont, color: white, alignment: .left)
            if preferences.bars {
                drawSegmentedBar(x: barX, y: y + 4.5, usedPercent: row.1?.usedPercent,
                                 segments: 10, segmentWidth: CGFloat(preferences.segmentWidth), segmentHeight: 7.8, gap: 5.2)
            }
            if preferences.percentages {
                let value = preferences.showUsed
                    ? UsageFormatting.percentLabel(row.1?.usedPercent.map { UsageFormatting.clamp($0) })
                    : UsageFormatting.balanceLabel(usedPercent: row.1?.usedPercent)
                drawText(value, in: NSRect(x: percentX, y: y, width: 42, height: textHeight), font: valueFont, color: row.1 == nil ? muted : white, alignment: .right)
            }
            if preferences.resetTimes {
                drawText(UsageFormatting.resetLabel(row.1?.resetsAt), in: NSRect(x: dateX, y: y, width: 82, height: textHeight), font: smallMonoFont, color: muted, alignment: .left)
            }
        }

        var tokenRows: [String] = []
        if preferences.yesterdayTokens { tokenRows.append("Yesterday \(UsageFormatting.tokenCount(snapshot.yesterdayTokens))") }
        if preferences.lifetimeTokens { tokenRows.append("Lifetime \(UsageFormatting.tokenCount(UsageFormatting.cumulativeTokenCount(snapshot)))") }
        for (index, text) in tokenRows.enumerated() {
            let y: CGFloat = tokenRows.count == 1 ? 7.5 : CGFloat(index) * 15
            drawText(text, in: NSRect(x: tokenX, y: y, width: 150, height: textHeight), font: tokenFont, color: white, alignment: .left)
        }

        if snapshot.source == "placeholder" {
            drawActivityDots()
        } else if errorMessage != nil {
            drawErrorDot()
        }
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawSegmentedBar(
        x: CGFloat,
        y: CGFloat,
        usedPercent: Double?,
        segments: Int,
        segmentWidth: CGFloat,
        segmentHeight: CGFloat,
        gap: CGFloat
    ) {
        let remaining = UsageFormatting.remainingPercent(usedPercent: usedPercent) ?? 0
        let displayed = preferences.showUsed ? (usedPercent.map { UsageFormatting.clamp($0) } ?? 0) : remaining
        let segmentValue = 100.0 / Double(segments)

        for index in 0..<segments {
            let left = x + CGFloat(index) * (segmentWidth + gap)
            let rect = NSRect(x: left, y: y, width: segmentWidth, height: segmentHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: segmentHeight / 2, yRadius: segmentHeight / 2)

            emptyFill.setFill()
            path.fill()
            emptyStroke.setStroke()
            path.lineWidth = 0.8
            path.stroke()

            let start = Double(index) * segmentValue
            let end = Double(index + 1) * segmentValue
            let fillRatio: Double
            if displayed <= start {
                fillRatio = 0
            } else if displayed >= end {
                fillRatio = 1
            } else {
                fillRatio = (displayed - start) / segmentValue
            }
            guard fillRatio > 0 else { continue }

            let fillWidth = max(1.2, segmentWidth * CGFloat(fillRatio))
            let fillRect = NSRect(x: left, y: y, width: min(segmentWidth, fillWidth), height: segmentHeight)
            let isHealthy = remaining > 30
            let fillColor = fillColor(for: remaining)

            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            fillColor.setFill()
            fillRect.fill()
            let highlightRect = NSRect(
                x: left + 1.4,
                y: y + 1.1,
                width: max(0, min(segmentWidth, fillWidth) - 2.8),
                height: segmentHeight * 0.34
            )
            let highlight = preferences.accent == .green ? greenTop : (fillColor.blended(withFraction: 0.6, of: .white) ?? fillColor)
            highlight.withAlphaComponent(isHealthy ? 0.88 : 0.44).setFill()
            NSBezierPath(
                roundedRect: highlightRect,
                xRadius: highlightRect.height / 2,
                yRadius: highlightRect.height / 2
            ).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func fillColor(for remaining: Double) -> NSColor {
        if remaining <= 10 { return danger }
        if remaining <= 30 { return warning }
        switch preferences.accent {
        case .green: return green
        case .blue: return NSColor(calibratedRed: 0.35, green: 0.78, blue: 1, alpha: 1)
        case .amber: return NSColor(calibratedRed: 1, green: 0.82, blue: 0.35, alpha: 1)
        }
    }

    private func drawActivityDots() {
        let baseX = CGFloat(preferences.contentWidth) - 18
        for index in 0..<4 {
            let alpha = 0.25 + CGFloat(index) * 0.16
            white.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: baseX + CGFloat(index) * 4.8, y: 11.5, width: 2.5, height: 2.5)).fill()
        }
    }

    private func drawErrorDot() {
        danger.setFill()
        NSBezierPath(ovalIn: NSRect(x: CGFloat(preferences.contentWidth) - 13, y: 11.5, width: 4.5, height: 4.5)).fill()
    }
}
