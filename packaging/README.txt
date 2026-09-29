Codex Usage Bar (Apple Silicon)

Shows customizable Codex five-hour and weekly usage, reset times, yesterday's
token usage, and lifetime token usage while Codex is frontmost.

Customize:
  Click the chart icon in the menu bar > Customize Touch Bar…
  Choose which items appear, used or remaining percentages, bar width, and color.
  The preview updates immediately. Your choices save automatically on this Mac.
  Settings open on first launch. Reopen the app from Finder to open them again.
  Codex display settings do not change the existing ZCode layout.

Requirements:
  Apple Silicon MacBook with a Touch Bar, macOS 12 or later.
  A local Codex sign-in is needed to refresh official usage.

Quit:
  Use the chart icon > Quit Codex Usage Bar.
  The helper will start again when reopened or at your next login.

Install:
  ./install.sh

Uninstall:
  ./uninstall.sh

The helper is installed to:
  ~/Applications/CodexTouchBarHelper.app

It starts at login through:
  ~/Library/LaunchAgents/com.local.codex-touchbar-helper.plist

Focus Codex or the ChatGPT Codex shell to display the Touch Bar panel.

The app is ad-hoc signed and not Apple-notarized. If macOS blocks it, verify
the downloaded archive checksum, then approve it in System Settings >
Privacy & Security > Open Anyway.

Project:
  https://github.com/ne0guy/codex-touchbar-usage
