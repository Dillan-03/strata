cask "strata-inspector" do
  version "0.8.1"
  sha256 "4459724fe3d969970ef4aef24ddbfcbc4d712553b507d3ca8a4c536e888c6d39"

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
