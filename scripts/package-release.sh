#!/usr/bin/env bash
# Zips build/Release/Strata.app into dist/Strata-<version>.zip and writes its SHA-256.
# Usage: scripts/package-release.sh <version>
set -euo pipefail

version="${1:?usage: package-release.sh <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Release/Strata.app"
dist="$root/dist"
archive="$dist/Strata-$version.zip"

bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [ "$bundle_version" != "$version" ]; then
  echo "::error title=Version mismatch::Strata.app reports $bundle_version but the release is $version. Update MARKETING_VERSION in App/project.yml."
  exit 1
fi

mkdir -p "$dist"
rm -f "$archive" "$archive.sha256"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd "$dist" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")

echo "Packaged $archive"
cat "$archive.sha256"
