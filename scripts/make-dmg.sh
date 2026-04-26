#!/usr/bin/env bash
# sclip — macOS release pipeline.
#
# Builds the universal .app, re-signs with Developer ID + hardened runtime,
# packages a drag-to-Applications DMG, submits to Apple notarization, and
# staples the ticket so the result opens cleanly on a fresh Mac.
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: Eren Kırkıl (TEAMID)" \
#   NOTARY_PROFILE=sclip-notary \
#   bash scripts/make-dmg.sh
#
# Prerequisites (one-time):
#   1. Apple Developer Program membership.
#   2. "Developer ID Application" certificate installed in login keychain.
#         Apple Developer → Certificates, Identifiers & Profiles → +
#         (NOT "Apple Distribution" — that one is App Store only.)
#   3. notarytool credentials saved to keychain:
#         xcrun notarytool store-credentials sclip-notary \
#             --apple-id you@example.com \
#             --team-id TEAMID \
#             --password app-specific-password
#         (App-specific password from appleid.apple.com → Sign-In and Security.)
#
# Notes:
#   - Output: dist/sclip-<version>.dmg (gitignored)
#   - The .app inside the DMG is signed, hardened-runtime-enabled, notarized,
#     and stapled — no Gatekeeper bypass needed on the user's machine.

set -euo pipefail

if [[ -z "${DEVELOPER_ID:-}" ]]; then
  echo "ERROR: DEVELOPER_ID env var not set."
  echo "Find it with: security find-identity -v -p codesigning"
  echo 'Example: export DEVELOPER_ID="Developer ID Application: Eren Kırkıl (ABCD123456)"'
  exit 1
fi
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "ERROR: NOTARY_PROFILE env var not set (notarytool keychain profile name)."
  exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# Read version from pubspec.yaml (e.g. 1.0.0+1 → 1.0.0)
VERSION=$(grep '^version:' pubspec.yaml | sed -E 's/version: *([0-9.]+).*/\1/')
APP_NAME="sclip"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="dist"
STAGE_DIR="$DIST_DIR/.dmg-staging"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

echo "==> Cleaning previous build"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
flutter clean >/dev/null

echo "==> Building release (universal, AOT)"
flutter build macos --release

echo "==> Re-signing .app with Developer ID + hardened runtime"
# --deep handles bundled Flutter.framework + plugins. --options runtime enables
# hardened runtime which notarization requires.
codesign --force --deep --options runtime \
  --entitlements macos/Runner/Release.entitlements \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E 'Authority|TeamIdentifier|flags'

echo "==> Staging DMG contents"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "==> Signing DMG"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

echo "==> Submitting to Apple notary service (this can take 1-15 minutes)"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

echo "==> Final Gatekeeper check"
spctl -a -t open --context context:primary-signature -v "$DMG_PATH" || true

echo
echo "✅ DONE: $DMG_PATH"
echo "   $(du -h "$DMG_PATH" | cut -f1) — drag the .app to /Applications on a fresh Mac, no warnings."
