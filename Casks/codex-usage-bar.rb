cask "codex-usage-bar" do
  version "0.4.1"
  sha256 "120093d51515e82127e7ab1f46edb63941b31e5625d678d72e7965cbdb81d423"

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
