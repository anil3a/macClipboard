#!/usr/bin/env bash
# Builds the downloadable app: build/MacClipboard-<version>.zip and .dmg (+ SHA-256 checksums).
#
# Signing uses CODESIGN_IDENTITY, else ./.codesign-identity, else ad-hoc (see build-app.sh).
# For a build that opens on any Mac without warnings, use a Developer ID certificate and notarize:
#
#   xcrun notarytool store-credentials macclipboard-notary --apple-id you@example.com --team-id TEAMID
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=macclipboard-notary \
#     scripts/release-github.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh direct

APP="build/MacClipboard.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="build/MacClipboard-$VERSION.zip"
DMG="build/MacClipboard-$VERSION.dmg"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Submitting for notarization…"
  ditto -c -k --keepParent "$APP" build/notarize.zip
  xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f build/notarize.zip
else
  echo "NOTARY_PROFILE not set: the build is not notarized."
fi

# Zip
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# Disk image with a shortcut to /Applications for drag-and-drop install
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "MacClipboard $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGING"
IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" "$DMG"
fi

( cd build && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "MacClipboard-$VERSION.sha256" )
cat "build/MacClipboard-$VERSION.sha256"
echo "Release files: $ZIP, $DMG"
