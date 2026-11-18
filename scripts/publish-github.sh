#!/usr/bin/env bash
# Builds the release locally and publishes it as a GitHub Release (no GitHub Actions needed).
#
#   1. Set the version in Resources/Info.plist (CFBundleShortVersionString), commit it.
#   2. make publish
#
# Creates and pushes tag v<version>, then uploads the .dmg, .zip and checksums with the GitHub CLI (gh).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v gh >/dev/null || { echo "Install the GitHub CLI: brew install gh" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Bump CFBundleShortVersionString in Resources/Info.plist." >&2
  exit 1
fi

./scripts/release-github.sh

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" -m "MacClipboard $VERSION"
fi
git push origin HEAD "$TAG"

NOTES="$(mktemp)"
cat > "$NOTES" <<EOF
## Install

1. Download **MacClipboard-$VERSION.dmg**, open it, and drag **MacClipboard** into **Applications**.
2. Open MacClipboard from Applications. If macOS says it can't verify the developer, open
   **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.
   (Or run: \`xattr -dr com.apple.quarantine /Applications/MacClipboard.app\`)
3. Allow **Accessibility** when asked, so the item you pick is pasted automatically.
4. Press **⇧⌘V** anywhere to open your clipboard history.

Requires macOS 13 Ventura or later. Universal: Apple silicon and Intel.

Signed by Anil Prajapati Newa. Not notarized by Apple.
Checksums (SHA-256) are in \`MacClipboard-$VERSION.sha256\`.
EOF

gh release create "$TAG" \
  "build/MacClipboard-$VERSION.dmg" \
  "build/MacClipboard-$VERSION.zip" \
  "build/MacClipboard-$VERSION.sha256" \
  --title "MacClipboard $VERSION" \
  --notes-file "$NOTES" \
  --verify-tag
rm -f "$NOTES"

gh release view "$TAG" --json url --jq .url
