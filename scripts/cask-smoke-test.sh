#!/usr/bin/env bash
# Installs Strata through Homebrew from a locally built zip, launches it, uninstalls it, reinstalls it, then zaps it,
# checking after each step that Claude Code configuration and repositories are untouched.
# Usage: scripts/cask-smoke-test.sh <version> <path to Strata-version.zip>
set -euo pipefail

version="${1:?usage: cask-smoke-test.sh <version> <zip>}"
zip="$(cd "$(dirname "${2:?usage: cask-smoke-test.sh <version> <zip>}")" && pwd)/$(basename "$2")"
root="$(cd "$(dirname "$0")/.." && pwd)"
tap="strata-ci/local"
sha="$(shasum -a 256 "$zip" | awk '{print $1}')"

# A stand-in for the user's own configuration, which must survive every step.
sentinel_dir="$HOME/.claude/skills/strata-smoke-test"
mkdir -p "$sentinel_dir"
printf -- "---\ndescription: Must survive uninstall\n---\n" > "$sentinel_dir/SKILL.md"
printf '{"mcpServers":{}}\n' > "$HOME/.strata-smoke-claude.json"
checksum_before="$(shasum -a 256 "$sentinel_dir/SKILL.md" "$HOME/.strata-smoke-claude.json")"

assert_config_untouched() {
  local now
  now="$(shasum -a 256 "$sentinel_dir/SKILL.md" "$HOME/.strata-smoke-claude.json")"
  if [ "$now" != "$checksum_before" ]; then
    echo "::error title=Cask smoke test::User configuration changed during $1"
    exit 1
  fi
}

export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ANALYTICS=1
brew untap "$tap" >/dev/null 2>&1 || true
brew tap-new --no-git "$tap" >/dev/null
tap_dir="$(brew --repository "$tap")"
mkdir -p "$tap_dir/Casks"
cask_file="$tap_dir/Casks/strata-inspector.rb"

echo "== audit (cask as published)"
"$root/scripts/render-cask.sh" "$version" "$sha" > "$cask_file"
brew style --cask "$tap/strata-inspector"
# Offline: the release URL doesn't exist yet. Signing is checked separately by sign-and-notarize.sh.
brew audit --cask --strict --no-signing "$tap/strata-inspector"

"$root/scripts/render-cask.sh" "$version" "$sha" "file://$zip" > "$cask_file"

echo "== install"
brew install --cask "$tap/strata-inspector"
test -d /Applications/Strata.app
xattr -dr com.apple.quarantine /Applications/Strata.app 2>/dev/null || true
"$root/scripts/smoke-test-app.sh" /Applications/Strata.app
assert_config_untouched install

echo "== uninstall"
brew uninstall --cask strata-inspector
test ! -e /Applications/Strata.app
assert_config_untouched uninstall

echo "== reinstall"
brew install --cask "$tap/strata-inspector"
test -d /Applications/Strata.app
assert_config_untouched reinstall

echo "== zap"
brew uninstall --zap --cask strata-inspector
test ! -e /Applications/Strata.app
for leftover in "$HOME/Library/Preferences/com.dillankerai.strata.plist" "$HOME/Library/Preferences/com.dillankerai.strata.uitests.plist"; do
  if [ -e "$leftover" ]; then
    echo "::error title=Cask smoke test::zap left $leftover behind"
    exit 1
  fi
done
assert_config_untouched zap

brew untap "$tap" >/dev/null
rm -rf "$sentinel_dir" "$HOME/.strata-smoke-claude.json"
echo "Homebrew install, launch, uninstall, reinstall and zap all passed; user configuration untouched."
