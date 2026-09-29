# Homebrew cask for PR Monitor. Lives in the BlockchainHB/homebrew-tap repository as
# Casks/pr-monitor.rb; update `version` and `sha256` (from dist/SHA256SUMS) on each release.
cask "pr-monitor" do
  version "1.0.0"
  sha256 "REPLACE_WITH_PRMonitor.dmg_SHA256"

  url "https://github.com/BlockchainHB/PR-Monitor/releases/download/v#{version}/PRMonitor.dmg"
  name "PR Monitor"
  desc "Menu bar app that watches CI checks and AI code reviewers on your pull requests"
  homepage "https://github.com/BlockchainHB/PR-Monitor"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "PRMonitor.app"

  uninstall quit: "com.neat.prmonitor"

  zap trash: [
    "~/Library/Caches/com.neat.prmonitor",
    "~/Library/Preferences/com.neat.prmonitor.plist",
  ]
end
