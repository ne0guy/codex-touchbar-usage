cask "codex-usage-bar" do
  version "0.4.0"
  sha256 "f733c57a5b61b3f142aaaeadcc7f51254740025e64c3b240aa4d61a9f6b85f37"

  url "https://github.com/ne0guy/codex-touchbar-usage/releases/download/v#{version}/CodexUsageBar-v#{version}-arm64.zip"
  name "Codex Usage Bar"
  desc "Customize Codex usage on the MacBook Pro Touch Bar"
  homepage "https://github.com/ne0guy/codex-touchbar-usage"

  depends_on arch: :arm64
  depends_on macos: :monterey

  installer script: "CodexUsageBar-v#{version}-arm64/install.sh"
  uninstall script: "CodexUsageBar-v#{version}-arm64/uninstall.sh"

  caveats <<~EOS
    The prebuilt Apple Silicon helper does not require Swift.
    It starts automatically at login and appears while Codex or ChatGPT is focused.
    Use the menu-bar chart icon to customize the displayed usage, token counts, and colors.
  EOS
end
