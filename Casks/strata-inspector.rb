cask "strata-inspector" do
  version "0.7.0"
  sha256 "ef44f53685536fe11e974bc558ff723cee0794056f16f9f967f9c1e37279f372"

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
