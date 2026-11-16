cask "strata-inspector" do
  version "0.2.0"
  sha256 "04de0719c1333ead125ba0fdbf9c833a88bfcc87c7789894f92b9b25845857a4"

  url "https://github.com/Dillan-03/strata/releases/download/v#{version}/Strata-#{version}.zip"
  name "Strata"
  desc "Inspect where your Claude Code configuration comes from"
  homepage "https://github.com/Dillan-03/strata"

  depends_on macos: :sequoia

  app "Strata.app"

  # Only Strata's own preferences and caches. Claude Code configuration (~/.claude, ~/.claude.json)
  # and your repositories are never touched.
  zap trash: [
    "~/Library/Caches/com.dillankerai.strata",
    "~/Library/HTTPStorages/com.dillankerai.strata",
    "~/Library/Preferences/com.dillankerai.strata.plist",
    "~/Library/Preferences/com.dillankerai.strata.uitests.plist",
    "~/Library/Saved Application State/com.dillankerai.strata.savedState",
  ]
end
