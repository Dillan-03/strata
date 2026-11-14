#!/usr/bin/env bash
# Builds a universal Release Strata.app into build/Release/Strata.app.
# Usage: scripts/build-release.sh
set -Eeuo pipefail
trap 'echo "::error title=${BASH_SOURCE[0]##*/}::Failed at line $LINENO: $BASH_COMMAND"' ERR

root="$(cd "$(dirname "$0")/.." && pwd)"
derived="$root/build/DerivedData"
output="$root/build/Release"

cd "$root/App"
xcodegen generate --quiet

xcodebuild build \
  -project Strata.xcodeproj \
  -scheme Strata \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  -quiet

rm -rf "$output"
mkdir -p "$output"
ditto "$derived/Build/Products/Release/Strata.app" "$output/Strata.app"

echo "Built $output/Strata.app"
lipo -archs "$output/Strata.app/Contents/MacOS/Strata"
