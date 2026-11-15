#!/usr/bin/env bash
# Renders App/Icon/AppIcon.svg into every PNG the macOS AppIcon set needs.
# Needs rsvg-convert (brew install librsvg). Usage: scripts/render-app-icon.sh
set -Eeuo pipefail
trap 'echo "${BASH_SOURCE[0]##*/}: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_svg="$root/App/Icon/AppIcon.svg"
output="$root/App/Strata/Assets.xcassets/AppIcon.appiconset"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found. Install it with: brew install librsvg" >&2; exit 1; }

for points in 16 32 128 256 512; do
  rsvg-convert -w "$points" -h "$points" -o "$output/icon_${points}x${points}.png" "$source_svg"
  rsvg-convert -w $((points * 2)) -h $((points * 2)) -o "$output/icon_${points}x${points}@2x.png" "$source_svg"
done
echo "Rendered 10 icons into ${output#"$root"/}"
