Codex Usage Bar 0.4.1 restores live usage refresh and prevents duplicate helper applications.

- Find the Codex CLI in the updated ChatGPT and Codex app bundles.
- Prevent multiple GUI helper copies from running at once.
- Stop older helper copies when upgrading through the installer.
- Fix cache replacement hangs with unique temporary files and atomic rename.
- Fetch current usage when checking with `--once-json`.

Download `CodexUsageBar-v0.4.1-arm64.zip` and its `.sha256` file. Verify the checksum, extract the archive, and run `./install.sh` from the extracted folder to upgrade your existing installation. Your customization preferences are preserved.

Requires an Apple Silicon MacBook with a Touch Bar and macOS 12 or later. A local Codex sign-in is required for official usage refresh. The app is ad-hoc signed and has not been Apple-notarized.

Validation: live app-server usage fetch, duplicate GUI launch rejection, 100 concurrent atomic cache writes, and the existing native UI checks.
