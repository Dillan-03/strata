#!/usr/bin/env bash
# Signs build/Release/Strata.app with a Developer ID certificate, notarises it and staples the ticket.
# Without credentials it ad-hoc signs instead and says so; it never pretends an unsigned build is signed.
#
# Environment (from GitHub Actions secrets; values are never printed):
#   APPLE_DEVELOPER_ID_CERTIFICATE_BASE64, APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD, APPLE_TEAM_ID,
#   APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_BASE64
#
# Writes "signed" or "unsigned" to build/Release/signing-status.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Release/Strata.app"
status_file="$root/build/Release/signing-status"
work="$(mktemp -d)"
keychain="$work/signing.keychain-db"

cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

required=(
  APPLE_DEVELOPER_ID_CERTIFICATE_BASE64
  APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
  APPLE_TEAM_ID
  APP_STORE_CONNECT_API_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  APP_STORE_CONNECT_API_KEY_BASE64
)
missing=()
for name in "${required[@]}"; do
  if [ -z "${!name:-}" ]; then missing+=("$name"); fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "::warning title=Unsigned build::Signing secrets missing (${missing[*]}). Ad-hoc signing only; Gatekeeper will warn users."
  codesign --force --deep --options runtime --sign - "$app"
  codesign --verify --strict --verbose=2 "$app"
  echo "unsigned" > "$status_file"
  exit 0
fi

password="$(openssl rand -base64 24)"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
echo "$APPLE_DEVELOPER_ID_CERTIFICATE_BASE64" | base64 --decode > "$work/certificate.p12"
security import "$work/certificate.p12" -k "$keychain" -P "$APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
existing_keychains=()
while IFS= read -r line; do
  existing_keychains+=("$(echo "$line" | tr -d '" ')")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$keychain" "${existing_keychains[@]}"

identity="$(security find-identity -v -p codesigning "$keychain" | grep "Developer ID Application" | grep "($APPLE_TEAM_ID)" | head -1 | awk -F'"' '{print $2}')"
if [ -z "$identity" ]; then
  echo "::error title=Signing::No Developer ID Application identity for the configured team was found in the certificate."
  exit 1
fi

codesign --force --deep --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --deep --verbose=2 "$app"

echo "$APP_STORE_CONNECT_API_KEY_BASE64" | base64 --decode > "$work/AuthKey.p8"
ditto -c -k --keepParent "$app" "$work/Strata-notarize.zip"
xcrun notarytool submit "$work/Strata-notarize.zip" \
  --key "$work/AuthKey.p8" \
  --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait \
  --timeout 30m
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

echo "signed" > "$status_file"
echo "Signed, notarised and stapled."
