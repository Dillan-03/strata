#!/usr/bin/env bash
# Writes the Homebrew cask for a release from packaging/strata-inspector.rb.template.
# Usage: scripts/render-cask.sh <version> <sha256> [url] > Casks/strata-inspector.rb
# The optional url overrides the GitHub release URL (used by CI to install a locally built zip).
set -Eeuo pipefail
trap 'echo "::error title=${BASH_SOURCE[0]##*/}::Failed at line $LINENO: $BASH_COMMAND"' ERR

version="${1:?usage: render-cask.sh <version> <sha256> [url]}"
sha256="${2:?usage: render-cask.sh <version> <sha256> [url]}"
# Single-quoted so Ruby's #{version} interpolation survives; inside ${3:-...} its braces would end the expansion early.
default_url='https://github.com/Dillan-03/strata/releases/download/v#{version}/Strata-#{version}.zip'
url="${3:-$default_url}"
root="$(cd "$(dirname "$0")/.." && pwd)"

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like 1.2.3" >&2
  exit 1
fi
if ! [[ "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "SHA-256 must be 64 lowercase hex characters" >&2
  exit 1
fi

if [[ "$url" == *[\|\&\\\"]* ]]; then
  echo "URL must not contain |, &, \\ or quotes" >&2
  exit 1
fi

sed -e "s|@VERSION@|$version|g" -e "s|@SHA256@|$sha256|g" -e "s|@URL@|$url|g" "$root/packaging/strata-inspector.rb.template"
