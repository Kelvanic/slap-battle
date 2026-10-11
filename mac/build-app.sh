#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="$ROOT/.build/SlapBattle.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN/SlapBattle" "$APP/Contents/MacOS/SlapBattle"
# Use the same Developer ID on every release so Keychain access stays consistent.
# Ad-hoc signing is useful for development but is not a release identity guarantee.
codesign --force --options runtime --sign "${SLAP_SIGN_IDENTITY:--}" --identifier com.kelvanic.slapbattle "$APP"
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"
if [[ "${SLAP_SIGN_IDENTITY:--}" == "-" ]]; then
  printf 'Development-only ad-hoc signature. Set SLAP_SIGN_IDENTITY for release builds.\n'
fi
