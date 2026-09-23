cask "codex-usage-bar" do
  version "0.3.7"
  sha256 "a99433f3e6262e719b23d62bd311345b4732c729e3e65b73c692cc5e8d82d614"

  url "https://github.com/ne0guy/codex-touchbar-usage/releases/download/v#{version}/CodexUsageBar-v#{version}-arm64.zip"
  name "Codex Usage Bar"
  desc "Track Codex 5-hour and weekly usage on the MacBook Pro Touch Bar"
  homepage "https://github.com/ne0guy/codex-touchbar-usage"

  depends_on arch: :arm64
  depends_on macos: :monterey

  installer script: "CodexUsageBar-v#{version}-arm64/install.sh"
  uninstall script: "CodexUsageBar-v#{version}-arm64/uninstall.sh"

  caveats <<~EOS
    The prebuilt Apple Silicon helper does not require Swift.
    It starts automatically at login and appears while Codex or ChatGPT is focused.
  EOS
end
