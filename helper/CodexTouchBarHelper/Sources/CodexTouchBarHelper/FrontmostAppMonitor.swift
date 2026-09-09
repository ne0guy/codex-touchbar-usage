import AppKit

enum ForegroundTarget: Hashable {
    case codex, zcode, none

    static func resolve(bundleIdentifier: String?, candidates: [String], codexTokens: Set<String>) -> Self {
        if bundleIdentifier == "dev.zcode.app" { return .zcode }
        if bundleIdentifier == "com.openai.codex" { return .codex }
        if candidates.contains("ZCode") { return .zcode }
        return candidates.contains(where: codexTokens.contains) ? .codex : .none
    }
}

final class FrontmostAppMonitor {
    private let targetTokens: Set<String>
    private let onChange: (ForegroundTarget) -> Void
    private var lastValue: ForegroundTarget?

    init(targetNames: Set<String>, onChange: @escaping (ForegroundTarget) -> Void) {
        self.targetTokens = targetNames
        self.onChange = onChange
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        evaluate(NSWorkspace.shared.frontmostApplication)
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        evaluate(app ?? NSWorkspace.shared.frontmostApplication)
    }

    private func evaluate(_ application: NSRunningApplication?) {
        let candidates = [
            application?.localizedName,
            application?.bundleIdentifier,
            application?.executableURL?.deletingPathExtension().lastPathComponent,
            application?.bundleURL?.deletingPathExtension().lastPathComponent
        ].compactMap { $0 }
        let target = ForegroundTarget.resolve(bundleIdentifier: application?.bundleIdentifier,
            candidates: candidates, codexTokens: targetTokens)
        guard target != lastValue else { return }
        lastValue = target
        if ProcessInfo.processInfo.environment["CODEX_TOUCHBAR_DEBUG"] == "1" {
            NSLog(
                "CodexTouchBarHelper: frontmost candidates=%@ visible=%@",
                candidates.joined(separator: ","),
                String(describing: target)
            )
        }
        DispatchQueue.main.async {
            self.onChange(target)
        }
    }
}
