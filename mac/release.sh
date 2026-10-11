#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${SLAP_VERSION:-}"
BUILD_NUMBER="${SLAP_BUILD_NUMBER:-}"
ARCH="${SLAP_ARCH:-}"
IDENTITY="${APPLE_SIGNING_IDENTITY:-${SLAP_SIGN_IDENTITY:-}}"
OUTPUT_DIR="${SLAP_OUTPUT_DIR:-$ROOT/dist}"
APP_NAME="SlapBattle"

fail() { printf 'release: %s\n' "$*" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'SLAP_VERSION must be a semantic version (for example 1.2.3).'
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail 'SLAP_BUILD_NUMBER must be a positive integer.'
case "$ARCH" in x86_64|arm64) ;; *) fail 'SLAP_ARCH must be x86_64 or arm64.' ;; esac
[[ -n "$IDENTITY" && "$IDENTITY" != "-" ]] || fail 'APPLE_SIGNING_IDENTITY (or SLAP_SIGN_IDENTITY) is required; refusing to create an unsigned release.'

PROFILE="${SLAP_NOTARY_PROFILE:-}"
API_KEY_ID="${APPLE_NOTARY_KEY_ID:-}"
API_ISSUER_ID="${APPLE_NOTARY_ISSUER_ID:-}"
API_KEY="${APPLE_NOTARY_PRIVATE_KEY:-}"
ALLOW_UNNOTARIZED="${SLAP_ALLOW_UNNOTARIZED:-0}"
[[ "$ALLOW_UNNOTARIZED" == 0 || "$ALLOW_UNNOTARIZED" == 1 ]] || fail 'SLAP_ALLOW_UNNOTARIZED must be 0 or 1.'
if [[ "$ALLOW_UNNOTARIZED" == 1 ]]; then
  printf 'WARNING: explicitly requested signed-only release; packages are NOT notarized.\n' >&2
fi
if [[ -n "$PROFILE" ]]; then
  if [[ -n "$API_KEY_ID$API_ISSUER_ID$API_KEY" ]]; then
    fail 'Use either SLAP_NOTARY_PROFILE or the complete App Store Connect API key credentials, not both.'
  fi
elif [[ "$ALLOW_UNNOTARIZED" != 1 ]]; then
  [[ -n "$API_KEY_ID" && -n "$API_ISSUER_ID" && -n "$API_KEY" ]] || fail 'Notarization is required: set SLAP_NOTARY_PROFILE locally or APPLE_NOTARY_KEY_ID, APPLE_NOTARY_ISSUER_ID, and APPLE_NOTARY_PRIVATE_KEY.'
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/slap-release.XXXXXX")"
KEYCHAIN="slap-release-$(uuidgen).keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)$(uuidgen)"
KEYCHAIN_CREATED=0
PREVIOUS_DEFAULT=""
PREVIOUS_SEARCH_KEYS=()
cleanup() {
  local status=$?
  set +e
  if [[ ${#PREVIOUS_SEARCH_KEYS[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${PREVIOUS_SEARCH_KEYS[@]}" >/dev/null 2>&1
  fi
  if [[ -n "$PREVIOUS_DEFAULT" ]]; then
    security default-keychain -d user -s "$PREVIOUS_DEFAULT" >/dev/null 2>&1
  fi
  if [[ "$KEYCHAIN_CREATED" == 1 ]]; then
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1
  fi
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

if [[ -n "${APPLE_CERTIFICATE_P12:-}" ]]; then
  [[ -n "${APPLE_CERTIFICATE_PASSWORD:-}" ]] || fail 'APPLE_CERTIFICATE_PASSWORD is required with APPLE_CERTIFICATE_P12.'
  umask 077
  CERT_FILE="$WORK/developer-id.p12"
  printf '%s' "$APPLE_CERTIFICATE_P12" | base64 --decode > "$CERT_FILE"
  [[ -s "$CERT_FILE" ]] || fail 'APPLE_CERTIFICATE_P12 decoded to an empty file.'
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  KEYCHAIN_CREATED=1
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security import "$CERT_FILE" -k "$KEYCHAIN" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
  PREVIOUS_DEFAULT="$(security default-keychain -d user 2>/dev/null | tr -d '"')"
  while IFS= read -r keychain; do
    keychain="${keychain#\"}"
    keychain="${keychain%\"}"
    [[ -n "$keychain" ]] && PREVIOUS_SEARCH_KEYS+=("$keychain")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s "$KEYCHAIN" "${PREVIOUS_SEARCH_KEYS[@]}"
  security default-keychain -d user -s "$KEYCHAIN"
fi

if [[ "$KEYCHAIN_CREATED" == 1 ]]; then
  IDENTITIES="$(security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null || true)"
else
  IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
fi
[[ "$IDENTITIES" == *"$IDENTITY"* ]] || fail "Signing identity '$IDENTITY' is not available in the configured keychain."

export SLAP_ARCH="$ARCH" SLAP_VERSION="$VERSION" SLAP_BUILD_NUMBER="$BUILD_NUMBER"
export SLAP_SIGN_IDENTITY="$IDENTITY" SLAP_OUTPUT_DIR="$WORK/build"
"$ROOT/build-app.sh"
APP="$WORK/build/$APP_NAME.app"
[[ -d "$APP" ]] || fail "Build did not produce $APP."

notarize() {
  local file="$1" response="$WORK/notary-response.json" status
  if [[ -n "$PROFILE" ]]; then
    xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json > "$response"
  else
    KEY_FILE="$WORK/notary-key.p8"
    printf '%s' "$API_KEY" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    xcrun notarytool submit "$file" --key "$KEY_FILE" --key-id "$API_KEY_ID" --issuer "$API_ISSUER_ID" --wait --output-format json > "$response"
    rm -f "$KEY_FILE"
  fi
  status="$(/usr/libexec/PlistBuddy -c 'Print :status' "$response" 2>/dev/null || /usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", ""))' "$response")"
  [[ "$status" == Accepted ]] || fail "Apple notarization did not return Accepted for $(basename "$file"): ${status:-missing status}."
}

mkdir -p "$OUTPUT_DIR"
DMG_NAME="$APP_NAME-$VERSION-macos-$ARCH.dmg"
ZIP_NAME="$APP_NAME-$VERSION-macos-$ARCH.zip"
if [[ "$ALLOW_UNNOTARIZED" != 1 ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/$ZIP_NAME"
  notarize "$WORK/$ZIP_NAME"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT_DIR/$ZIP_NAME"
STAGE="$WORK/dmg-root"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION ($ARCH)" -srcfolder "$STAGE" -ov -format UDZO "$OUTPUT_DIR/$DMG_NAME" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$OUTPUT_DIR/$DMG_NAME"
codesign --verify --strict --verbose=2 "$OUTPUT_DIR/$DMG_NAME"
if [[ "$ALLOW_UNNOTARIZED" != 1 ]]; then
  notarize "$OUTPUT_DIR/$DMG_NAME"
  xcrun stapler staple "$OUTPUT_DIR/$DMG_NAME"
  xcrun stapler validate "$OUTPUT_DIR/$DMG_NAME"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$OUTPUT_DIR/$DMG_NAME"
fi

printf '%s\n' "$OUTPUT_DIR/$DMG_NAME" "$OUTPUT_DIR/$ZIP_NAME"
