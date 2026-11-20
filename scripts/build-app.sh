#!/usr/bin/env bash
# Builds MacClipboard.app with SwiftPM (no Xcode project needed).
#
#   scripts/build-app.sh [direct|appstore]
#
#   direct    (default) GitHub / website build: hardened runtime, not sandboxed  -> build/MacClipboard.app
#   appstore  Mac App Store build: sandboxed                                    -> build/AppStore/MacClipboard.app
#
# Environment:
#   CODESIGN_IDENTITY     signing identity. If unset, the name in ./.codesign-identity (not committed)
#                         is used, else "-" (ad-hoc, fine for local use)
#   BUNDLE_ID             default io.github.anil3a.MacClipboard
#   VERSION, BUILD_NUMBER override the version in Resources/Info.plist / the commit count
#   UNIVERSAL=0           build only for this Mac's architecture (faster)
#   TEAM_ID, PROVISIONING_PROFILE   appstore only (see scripts/package-appstore.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

FLAVOR="${1:-direct}"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  IDENTITY="$CODESIGN_IDENTITY"
elif [[ -s .codesign-identity ]]; then
  IDENTITY="$(head -n 1 .codesign-identity)"
else
  IDENTITY="-"
fi
BUNDLE_ID="${BUNDLE_ID:-io.github.anil3a.MacClipboard}"
PLIST_BUDDY=/usr/libexec/PlistBuddy
VERSION="${VERSION:-$($PLIST_BUDDY -c 'Print CFBundleShortVersionString' Resources/Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

case "$FLAVOR" in
  direct)   APP="build/MacClipboard.app";          ENTITLEMENTS="Resources/MacClipboard.entitlements" ;;
  appstore) APP="build/AppStore/MacClipboard.app"; ENTITLEMENTS="Resources/MacClipboard-AppStore.entitlements" ;;
  *) echo "Usage: $0 [direct|appstore]" >&2; exit 1 ;;
esac

# --- Compile -----------------------------------------------------------------
if [[ "${UNIVERSAL:-1}" == "1" ]]; then
  BINARIES=()
  mkdir -p build
  for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx13.0"
    # Newer SwiftPM writes every triple to the same bin path, so copy each slice out before the next build.
    cp "$(swift build -c release --triple "$ARCH-apple-macosx13.0" --show-bin-path)/MacClipboard" "build/MacClipboard-$ARCH"
    BINARIES+=("build/MacClipboard-$ARCH")
  done
  lipo -create "${BINARIES[@]}" -output build/MacClipboard-universal
  BINARY="build/MacClipboard-universal"
else
  swift build -c release
  BINARY="$(swift build -c release --show-bin-path)/MacClipboard"
fi

# --- Bundle ------------------------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/MacClipboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

$PLIST_BUDDY -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
$PLIST_BUDDY -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
$PLIST_BUDDY -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# --- Entitlements ------------------------------------------------------------
SIGN_ENTITLEMENTS="$(mktemp -t macclipboard-entitlements).plist"
cp "$ENTITLEMENTS" "$SIGN_ENTITLEMENTS"
if [[ "$FLAVOR" == "appstore" ]]; then
  if [[ -n "${TEAM_ID:-}" ]]; then
    $PLIST_BUDDY -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$SIGN_ENTITLEMENTS"
    $PLIST_BUDDY -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$SIGN_ENTITLEMENTS"
  fi
  if [[ -n "${PROVISIONING_PROFILE:-}" ]]; then
    cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  fi
fi

# --- Sign --------------------------------------------------------------------
SIGN_ARGS=(--force --options runtime --entitlements "$SIGN_ENTITLEMENTS" --sign "$IDENTITY")
# Secure timestamps come from Apple and are only needed for Apple-issued certificates.
if [[ "$IDENTITY" =~ ^(Developer\ ID|Apple\ Distribution|Apple\ Development|3rd\ Party) ]]; then
  SIGN_ARGS+=(--timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=1 "$APP"
rm -f "$SIGN_ENTITLEMENTS"

echo "Built $APP ($FLAVOR, version $VERSION build $BUILD_NUMBER, signed with '$IDENTITY')"
