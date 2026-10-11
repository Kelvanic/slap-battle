#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
ARCH="${SLAP_ARCH:-$(uname -m)}"
VERSION="${SLAP_VERSION:-}"
BUILD_NUMBER="${SLAP_BUILD_NUMBER:-}"
OUTPUT_DIR="${SLAP_OUTPUT_DIR:-$ROOT/.build}"
case "$ARCH" in x86_64|arm64) ;; *) printf 'Unsupported SLAP_ARCH: %s\n' "$ARCH" >&2; exit 1 ;; esac
[[ -z "$VERSION" || "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'SLAP_VERSION must be a semantic version.\n' >&2; exit 1; }
[[ -z "$BUILD_NUMBER" || "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { printf 'SLAP_BUILD_NUMBER must be a positive integer.\n' >&2; exit 1; }
swift build -c release --arch "$ARCH"
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)"
APP="$OUTPUT_DIR/SlapBattle.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "$VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
cp "$BIN/SlapBattle" "$APP/Contents/MacOS/SlapBattle"
# Ad-hoc signing is for local development only; release.sh requires a Developer ID identity.
codesign --force --options runtime --sign "${SLAP_SIGN_IDENTITY:--}" --identifier com.kelvanic.slapbattle "$APP"
codesign --verify --strict "$APP"
printf 'Built %s (%s)\n' "$APP" "$ARCH"
if [[ "${SLAP_SIGN_IDENTITY:--}" == "-" ]]; then
  printf 'Development-only ad-hoc signature. Set SLAP_SIGN_IDENTITY for release builds.\n'
fi
