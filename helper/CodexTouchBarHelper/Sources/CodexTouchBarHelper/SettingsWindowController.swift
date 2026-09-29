import AppKit
import CodexTouchBarCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private(set) var preferences: TouchBarPreferences
    var onChange: ((TouchBarPreferences) -> Void)?
    private let preview = UsageTouchBarView(frame: NSRect(x: 0, y: 0, width: 664, height: 30))
    private let previewCaption = NSTextField(labelWithString: "Example data · changes appear instantly")
    private var checks: [String: NSButton] = [:]
    private let percentageMode = NSPopUpButton()
    private let barSize = NSPopUpButton()
    private let accent = NSPopUpButton()

    init(preferences: TouchBarPreferences) {
        self.preferences = preferences
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Customize your Touch Bar"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        synchronizeControls()
        preview.alphaValue = 1
        preview.snapshot = Self.exampleSnapshot()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateSnapshot(_ snapshot: UsageSnapshot) {
        guard snapshot.source != "placeholder" else { return }
        preview.snapshot = snapshot
        previewCaption.stringValue = "Your latest usage · changes appear instantly"
    }

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        return field
    }

    private func vertical(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func checkbox(_ title: String, key: String) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed))
        button.identifier = NSUserInterfaceItemIdentifier(key)
        checks[key] = button
        return button
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let heading = label("Your Touch Bar, your way.", size: 26, weight: .bold)
        let subtitle = label("Choose the Codex usage details you want to keep at a glance.")
        subtitle.textColor = .secondaryLabelColor
        let title = vertical([heading, subtitle], spacing: 6)

        let previewBox = NSView()
        previewBox.wantsLayer = true
        previewBox.layer?.backgroundColor = NSColor.black.cgColor
        previewBox.layer?.cornerRadius = 12
        previewBox.addSubview(preview)
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewBox.heightAnchor.constraint(equalToConstant: 74),
            preview.leadingAnchor.constraint(equalTo: previewBox.leadingAnchor, constant: 16),
            preview.trailingAnchor.constraint(equalTo: previewBox.trailingAnchor, constant: -16),
            preview.centerYAnchor.constraint(equalTo: previewBox.centerYAnchor),
            preview.heightAnchor.constraint(equalToConstant: 30)
        ])
        previewCaption.font = .systemFont(ofSize: 11)
        previewCaption.textColor = .secondaryLabelColor
        let previewSection = vertical([previewBox, previewCaption], spacing: 8)
        previewBox.widthAnchor.constraint(equalTo: previewSection.widthAnchor).isActive = true

        let limits = vertical([
            label("USAGE WINDOWS", size: 11, weight: .semibold),
            checkbox("Five-hour usage", key: "fiveHour"),
            checkbox("Weekly usage", key: "weekly"),
            checkbox("Usage bars", key: "bars"),
            checkbox("Percentages", key: "percentages"),
            checkbox("Reset dates and times", key: "resetTimes")
        ])
        let totals = vertical([
            label("TOKEN COUNTS", size: 11, weight: .semibold),
            checkbox("Yesterday’s tokens", key: "yesterdayTokens"),
            checkbox("Lifetime tokens", key: "lifetimeTokens"),
            label("Hide items to make more room for what matters.", size: 11)
        ])
        (totals.arrangedSubviews.last as? NSTextField)?.textColor = .secondaryLabelColor
        let columns = NSStackView(views: [limits, totals])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 32

        percentageMode.addItems(withTitles: ["Remaining", "Used"])
        barSize.addItems(withTitles: ["Standard", "Compact"])
        accent.addItems(withTitles: ["Lime", "Sky blue", "Amber"])
        for popup in [percentageMode, barSize, accent] {
            popup.target = self
            popup.action = #selector(changed)
        }
        let style = NSStackView(views: [vertical([label("Percentages show", size: 11, weight: .semibold), percentageMode]),
                                       vertical([label("Bar width", size: 11, weight: .semibold), barSize]),
                                       vertical([label("Bar color", size: 11, weight: .semibold), accent])])
        style.distribution = .fillEqually
        style.spacing = 24

        let reset = NSButton(title: "Restore defaults", target: self, action: #selector(restoreDefaults))
        let done = NSButton(title: "Done", target: self, action: #selector(closeSettings))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let saved = label("Saved automatically on this Mac", size: 11)
        saved.textColor = .secondaryLabelColor
        let spacer = NSView()
        let footer = NSStackView(views: [reset, saved, spacer, done])
        footer.orientation = .horizontal
        footer.spacing = 12
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let scope = label("Settings apply to Codex. ZCode keeps its existing layout.", size: 11)
        scope.textColor = .secondaryLabelColor
        let root = vertical([title, previewSection, columns, style, scope, footer], spacing: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32)
        ])
        for view in [previewSection, columns, style, footer] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }

    private func synchronizeControls() {
        let values = ["fiveHour": preferences.fiveHour, "weekly": preferences.weekly,
                      "bars": preferences.bars, "percentages": preferences.percentages,
                      "resetTimes": preferences.resetTimes, "yesterdayTokens": preferences.yesterdayTokens,
                      "lifetimeTokens": preferences.lifetimeTokens]
        for (key, value) in values { checks[key]?.state = value ? .on : .off }
        percentageMode.selectItem(at: preferences.showUsed ? 1 : 0)
        barSize.selectItem(at: preferences.barSize == .compact ? 1 : 0)
        accent.selectItem(at: TouchBarPreferences.Accent.allCases.firstIndex(of: preferences.accent) ?? 0)
        preview.preferences = preferences
    }

    @objc private func changed(_ sender: Any?) {
        func enabled(_ key: String) -> Bool { checks[key]?.state == .on }
        preferences.fiveHour = enabled("fiveHour")
        preferences.weekly = enabled("weekly")
        preferences.bars = enabled("bars")
        preferences.percentages = enabled("percentages")
        preferences.resetTimes = enabled("resetTimes")
        preferences.yesterdayTokens = enabled("yesterdayTokens")
        preferences.lifetimeTokens = enabled("lifetimeTokens")
        preferences.showUsed = percentageMode.indexOfSelectedItem == 1
        preferences.barSize = barSize.indexOfSelectedItem == 1 ? .compact : .standard
        preferences.accent = TouchBarPreferences.Accent.allCases[accent.indexOfSelectedItem]
        apply()
    }

    @objc private func restoreDefaults() {
        preferences = TouchBarPreferences()
        synchronizeControls()
        apply()
    }

    private func apply() {
        do {
            try preferences.save()
            preview.preferences = preferences
            onChange?(preferences)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func closeSettings() { window?.close() }

    private static func exampleSnapshot() -> UsageSnapshot {
        var snapshot = UsageSnapshot.placeholder
        let now = Int(Date().timeIntervalSince1970)
        snapshot.primary = LimitWindow(name: "primary", usedPercent: 24, windowMinutes: 300, resetsAt: now + 7200)
        snapshot.secondary = LimitWindow(name: "secondary", usedPercent: 51, windowMinutes: 10080, resetsAt: now + 345600)
        snapshot.yesterdayTokens = 79173391
        snapshot.cumulativeTokens = 483391079
        snapshot.source = "example"
        return snapshot
    }
}
