# Customizing Codex Usage Bar

Version 0.4.0 adds a native Mac settings window. Click the chart icon in the menu
bar and choose **Customize Touch Bar…**, or reopen the app from Finder.
The window also opens the first time you launch this version.

Choose any combination of:

- Five-hour and weekly usage windows
- Usage bars and numeric percentages
- Reset dates and times
- Yesterday’s and lifetime token counts

Switch between remaining and used percentages, choose standard or compact bars,
and pick lime, sky blue, or amber. Low remaining quota still uses warning colors.
Hidden columns collapse automatically. A single selected row is centered.

The preview responds immediately and uses your latest cached usage when available.
Before usage is available, it shows clearly labelled example data. Changes save
automatically in this Mac’s app preferences and apply to the live Codex Touch Bar.
**Restore defaults** brings back the compact v1 layout.

These settings currently apply to Codex. The existing ZCode view remains available
with its current layout.

## Installable package

The release archive includes the app, an installer, an uninstaller, and instructions.
It supports Apple Silicon Macs with a Touch Bar running macOS 12 or later.
Codex usage requires a local Codex sign-in. Token counts come from the existing
usage sources; changing display preferences does not change usage collection.

Build a release with:

```sh
bash scripts/package_release.sh
```

The result is `dist/CodexUsageBar-v0.4.0-arm64.zip` and a SHA-256 checksum.
The current build uses an ad-hoc signature. It is suitable for local testing and
manual installation; it has not been Apple-notarized. A public distribution that
avoids the unsigned-developer approval flow needs Developer ID signing and Apple
notarization before publication.

The installed helper starts at login and restarts after an unexpected exit. **Quit
Codex Usage Bar** stops it until it is reopened or the next login.

## Development checkpoint

The Git tag `v1` preserves the verified layout before customization. The working
branch for this version is `codex/customization-app`.
