#!/usr/bin/env bash
# sclip.app paketleyici: swift build -> dist/build/sclip.app (ad-hoc imzalı).
# Kullanım: scripts/build-app.sh [debug|release]   (varsayılan: debug)
# Developer ID imzası ve DMG: scripts/make-dmg.sh (Task 32).
set -euo pipefail

CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "Kullanım: $0 [debug|release]" >&2; exit 64 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/mac"
APP="$ROOT/dist/build/sclip.app"

if [[ "$CONFIG" == "release" ]]; then
  ENTITLEMENTS="$PKG/Resources/sclip.entitlements"
else
  ENTITLEMENTS="$PKG/Resources/sclip-debug.entitlements"
fi

swift build -c "$CONFIG" --package-path "$PKG"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$PKG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/sclip" "$APP/Contents/MacOS/sclip"
cp "$PKG/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$PKG/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Metin kataloğu Task 7'de eklenir; o zamana dek yokluğu hata değildir.
if [[ -f "$ROOT/spec/strings.tr.json" ]]; then
  cp "$ROOT/spec/strings.tr.json" "$APP/Contents/Resources/strings.tr.json"
fi

codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP"

echo "Hazır: $APP ($CONFIG)"
