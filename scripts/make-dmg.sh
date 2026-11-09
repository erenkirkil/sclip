#!/usr/bin/env bash
# sclip — macOS native release pipeline (v2.0.0+).
#
# Builds the native Swift release .app bundle, re-signs with Developer ID +
# hardened runtime (--options runtime), packages a drag-to-Applications DMG,
# and optionally submits to Apple notarization + staples the ticket when
# NOTARY_PROFILE is provided.
#
# Usage:
#   bash scripts/make-dmg.sh
#
# With notarization:
#   DEVELOPER_ID="Developer ID Application: EREN KIRKIL (992XYS9346)" \
#   NOTARY_PROFILE=sclip-notary \
#   bash scripts/make-dmg.sh

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

DEVELOPER_ID="${DEVELOPER_ID:-}"
if [[ -z "$DEVELOPER_ID" ]]; then
  DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application:/ { print $2; exit }')"
fi
if [[ -z "$DEVELOPER_ID" ]]; then
  echo "HATA: DEVELOPER_ID bulunamadı. Anahtarlıkta 'Developer ID Application' sertifikası olmalı." >&2
  echo "Kontrol: security find-identity -v -p codesigning" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" mac/Resources/Info.plist)"
APP_NAME="sclip"
APP_PATH="dist/build/${APP_NAME}.app"
DIST_DIR="dist"
STAGE_DIR="$DIST_DIR/.dmg-staging"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

echo "==> Derleniyor: native release (${APP_NAME} ${VERSION})"
bash scripts/build-app.sh release

echo "==> Sertleştirilmiş çalışma zamanı (hardened runtime) ile imzalanıyor: $DEVELOPER_ID"
codesign --force --options runtime \
  --entitlements mac/Resources/sclip.entitlements \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "$APP_PATH"

echo "==> İmza doğrulanıyor"
codesign --verify --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E 'Authority|TeamIdentifier|flags'

echo "==> DMG sahnesi hazırlanıyor (dist/ altındaki diğer dosyalar korunur)"
mkdir -p "$STAGE_DIR"
rsync -a --delete "$APP_PATH/" "$STAGE_DIR/${APP_NAME}.app/"
ln -sfn /Applications "$STAGE_DIR/Applications"

echo "==> DMG oluşturuluyor: $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "==> DMG imzalanıyor"
codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Apple noter servisine gönderiliyor (NOTARY_PROFILE=$NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo "==> Noter bileti zımbalanıyor (staple)"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl -a -t open --context context:primary-signature -v "$DMG_PATH" || true
else
  echo "ℹ️  NOTARY_PROFILE tanımlı değil; noter adımı atlandı (imzalı DMG üretildi)."
  echo "   Noter onayı için: NOTARY_PROFILE=sclip-notary bash scripts/make-dmg.sh"
fi

echo
echo "✅ HAZIR: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
