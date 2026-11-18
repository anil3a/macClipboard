#!/usr/bin/env bash
# Builds a zip for GitHub Releases / your website.
#
# Without credentials it produces an ad-hoc signed zip (users must right-click › Open the first time).
# For a build that opens without warnings, sign with a Developer ID and notarize:
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

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Submitting for notarization…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
else
  echo "NOTARY_PROFILE not set: zip is not notarized."
fi

shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Release archive: $ZIP"
