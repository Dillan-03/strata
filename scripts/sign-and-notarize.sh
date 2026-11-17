#!/usr/bin/env bash
# Signs build/Release/Strata.app with a Developer ID certificate, notarises it and staples the ticket.
# Without credentials it ad-hoc signs instead and says so; it never pretends an unsigned build is signed.
#
# Environment (from GitHub Actions secrets; values are never printed):
#   APPLE_DEVELOPER_ID_CERTIFICATE_BASE64, APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD, APPLE_TEAM_ID,
#   APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_BASE64
#
# Writes "signed" or "unsigned" to build/Release/signing-status.
set -Eeuo pipefail
# Line number only: never echo the failing command here, in case it references a secret.
trap 'echo "::error title=${BASH_SOURCE[0]##*/}::Failed at line $LINENO"' ERR

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

# Prints the first Developer ID Application identity for the team in `security find-identity` output.
# awk rather than grep: under pipefail a grep that matches nothing ends the script before the messages below.
team_developer_id() {
  awk -F'"' -v team="($APPLE_TEAM_ID)" \
    '!found && index($2, "Developer ID Application: ") == 1 && index($2, team) { print $2; found = 1 }'
}

all_identities="$(security find-identity -p codesigning "$keychain")"
valid_identities="$(security find-identity -v -p codesigning "$keychain")"
identity="$(team_developer_id <<< "$valid_identities")"
if [ -z "$identity" ]; then
  if [ -n "$(team_developer_id <<< "$all_identities")" ]; then
    echo "::error title=Signing::The .p12 has the Developer ID Application certificate, but macOS doesn't trust it. Install Apple's Developer ID - G2 intermediate certificate from https://www.apple.com/certificateauthority/."
  else
    # Only the certificate type before the colon, never the holder's name.
    kinds="$(awk -F'"' 'NF >= 3 { sub(/:.*/, "", $2); print $2 }' <<< "$all_identities" | sort -u | paste -sd ',' - | sed 's/,/, /g')"
    echo "::error title=Signing::The .p12 has no Developer ID Application identity for APPLE_TEAM_ID. It contains: ${kinds:-no signing identities}. In Keychain Access, export the Developer ID Application certificate with its private key from My Certificates, and check APPLE_TEAM_ID matches the ID in brackets in its name."
  fi
  exit 1
fi

# Apple's timestamp server sometimes doesn't answer, and codesign fails with "A timestamp was expected but was not found".
for attempt in 1 2 3; do
  if codesign --force --deep --options runtime --timestamp --sign "$identity" "$app"; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    echo "::error title=Signing::codesign failed 3 times. If it says a timestamp was expected, Apple's timestamp server is down: check https://developer.apple.com/system-status/ and re-run."
    exit 1
  fi
  echo "::warning title=Signing::codesign attempt $attempt failed. Trying again in 20 seconds."
  sleep 20
done
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
