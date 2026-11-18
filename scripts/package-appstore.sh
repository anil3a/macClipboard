#!/usr/bin/env bash
# Builds the sandboxed app and wraps it in a signed .pkg for App Store Connect.
# Requires a paid Apple Developer Program membership.
#
#   CODESIGN_IDENTITY="Apple Distribution: Your Name (TEAMID)" \
#   INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)" \
#   TEAM_ID=TEAMID \
#   PROVISIONING_PROFILE=~/Downloads/MacClipboard_AppStore.provisionprofile \
#     scripts/package-appstore.sh
#
# Then upload build/MacClipboard-AppStore.pkg with Apple's Transporter app.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CODESIGN_IDENTITY:?set CODESIGN_IDENTITY (Apple Distribution certificate)}"
: "${INSTALLER_IDENTITY:?set INSTALLER_IDENTITY (Mac Installer Distribution certificate)}"
: "${TEAM_ID:?set TEAM_ID}"
: "${PROVISIONING_PROFILE:?set PROVISIONING_PROFILE (Mac App Store provisioning profile)}"

./scripts/build-app.sh appstore

PKG="build/MacClipboard-AppStore.pkg"
productbuild --component build/AppStore/MacClipboard.app /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
echo "App Store package: $PKG"
