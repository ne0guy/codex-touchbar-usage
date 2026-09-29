import AppKit
import CodexTouchBarCore

@main
struct TouchBarUIHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let tokens: Set<String> = ["Codex", "ChatGPT", "com.openai.codex"]
        precondition(ForegroundTarget.resolve(bundleIdentifier: "dev.zcode.app", candidates: ["ChatGPT"], codexTokens: tokens) == .zcode)
        precondition(ForegroundTarget.resolve(bundleIdentifier: "com.openai.codex", candidates: ["ZCode"], codexTokens: tokens) == .codex)
        precondition(ForegroundTarget.resolve(bundleIdentifier: "com.apple.Terminal", candidates: ["Terminal"], codexTokens: tokens) == .none)
        precondition(ForegroundTarget.resolve(bundleIdentifier: nil, candidates: ["ChatGPT"], codexTokens: tokens) == .codex)
        let controller = TouchBarController(usesSystemTouchBar: false)
        var timings: [Double] = []
        for _ in 0..<100 {
            let start = CFAbsoluteTimeGetCurrent()
            controller.show(for: .codex)
            controller.show(for: .zcode)
            controller.hideAnimated()
            controller.show(for: .codex)
            timings.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        precondition(controller.isPresented && controller.target == .codex, "late hide must not dismiss current panel")
        controller.hideAnimated()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        precondition(!controller.isPresented)
        timings.sort()
        print("100 rapid synthetic target cycles: PASS; p95 dispatch ms=\(timings[94]) (system presentation disabled)")

        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/codex-touchbar-preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "TouchBarPreferences.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(TouchBarPreferences.load(from: defaults) == TouchBarPreferences())
        var customized = TouchBarPreferences()
        customized.fiveHour = false
        customized.bars = false
        customized.showUsed = true
        customized.accent = .blue
        customized.barSize = .compact
        try customized.save(to: defaults)
        precondition(TouchBarPreferences.load(from: defaults) == customized, "preferences must survive reloading")
        defaults.set(Data("broken settings".utf8), forKey: TouchBarPreferences.defaultsKey)
        precondition(TouchBarPreferences.load(from: defaults) == TouchBarPreferences(), "corrupt settings must use defaults")
        for mask in 0..<128 {
            for size in TouchBarPreferences.BarSize.allCases {
                var value = TouchBarPreferences()
                value.fiveHour = mask & 1 != 0
                value.weekly = mask & 2 != 0
                value.bars = mask & 4 != 0
                value.percentages = mask & 8 != 0
                value.resetTimes = mask & 16 != 0
                value.yesterdayTokens = mask & 32 != 0
                value.lifetimeTokens = mask & 64 != 0
                value.barSize = size
                precondition(value.tokenX >= 8 && value.contentWidth <= 636, "every layout must fit the compact panel")
            }
        }
        print("Preferences round trip, corrupt-data recovery, and 256 layouts: PASS")

        let codex = UsageTouchBarView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
        codex.alphaValue = 1
        var original = UsageSnapshot.placeholder
        original.primary = LimitWindow(name: "codex", usedPercent: 39, windowMinutes: 10080, resetsAt: 1785258135)
        original.resetCreditsAvailable = 3
        original.resetCreditsExpiresAt = 1785109710
        original.yesterdayTokens = 791733914
        original.cumulativeTokens = 15439107907
        original.source = "app-server"
        codex.snapshot = original
        try render(codex, to: directory.appendingPathComponent("codex.png"))
        original.primary = LimitWindow(name: "primary", usedPercent: 24, windowMinutes: 300, resetsAt: 1785258135)
        codex.snapshot = original
        codex.preferences = customized
        try render(codex, to: directory.appendingPathComponent("customized.png"))
        var tokensOnly = TouchBarPreferences()
        tokensOnly.fiveHour = false
        tokensOnly.weekly = false
        codex.preferences = tokensOnly
        try render(codex, to: directory.appendingPathComponent("tokens-only.png"))
        let settings = SettingsWindowController(preferences: TouchBarPreferences())
        var captured: TouchBarPreferences?
        settings.onChange = { captured = $0 }
        let oldPreferences = UserDefaults.standard.object(forKey: TouchBarPreferences.defaultsKey)
        defer {
            if let oldPreferences { UserDefaults.standard.set(oldPreferences, forKey: TouchBarPreferences.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: TouchBarPreferences.defaultsKey) }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let views = descendants(settings.window!.contentView!)
        let weeklyCheckbox = views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "weekly" }!
        weeklyCheckbox.performClick(nil)
        precondition(captured?.weekly == false, "checkbox must apply changes")
        precondition(TouchBarPreferences.load().weekly == false, "checkbox must save changes")
        views.compactMap { $0 as? NSButton }.first { $0.title == "Restore defaults" }!.performClick(nil)
        precondition(captured == TouchBarPreferences(), "restore must reset every option")
        settings.window!.contentView!.layoutSubtreeIfNeeded()
        for control in views.compactMap({ $0 as? NSControl }) {
            let rect = control.convert(control.bounds, to: settings.window!.contentView!)
            precondition(settings.window!.contentView!.bounds.contains(rect), "settings controls must fit the window: \(control)")
        }
        try render(settings.window!.contentView!, to: directory.appendingPathComponent("settings.png"), background: .windowBackgroundColor)
        print("Settings checkbox, persistence, restore defaults, and window layout: PASS")
        let zcode = ZCodeTouchBarView(frame: codex.frame)
        var z = ZCodeUsageSnapshot.placeholder
        z.provider = .go
        z.goRolling = ZCodeQuota(usedPercent: 23, resetsAt: 1788939447)
        z.goWeekly = ZCodeQuota(usedPercent: 81, resetsAt: 1789344000)
        z.goMonthly = ZCodeQuota(usedPercent: 94, resetsAt: 1789004067)
        z.glmPrimary = ZCodeQuota(usedPercent: 27, resetsAt: 1788929097)
        z.glmWeekly = ZCodeQuota(usedPercent: 72, resetsAt: 1789106366)
        z.todayTokens = 12345678
        z.cumulativeTokens = 1234567890
        z.statsReady = true
        zcode.snapshot = z
        try render(zcode, to: directory.appendingPathComponent("go.png"))
        z.provider = .glm
        zcode.snapshot = z
        try render(zcode, to: directory.appendingPathComponent("glm.png"))
        (zcode.subviews.first as? NSButton)?.performClick(nil)
        precondition(zcode.showsDetails)
        try render(zcode, to: directory.appendingPathComponent("details.png"))
        print("Native AppKit rendering: PASS")
    }

    @MainActor static func render(_ view: NSView, to url: URL, background: NSColor = .black) throws {
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = background
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        window.orderBack(nil)
        window.display()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        defer { window.orderOut(nil) }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("bitmap unavailable") }
        view.cacheDisplay(in: view.bounds, to: rep)
        if background != .black {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), url.path]
            try capture.run()
            capture.waitUntilExit()
            guard capture.terminationStatus == 0 else { throw NSError(domain: "SettingsWindowCapture", code: Int(capture.terminationStatus)) }
            return
        }
        guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG unavailable") }
        try data.write(to: url)
    }
}
