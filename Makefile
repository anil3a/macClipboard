APP := build/MacClipboard.app

.PHONY: app run install appstore release test icon clean

## Build build/MacClipboard.app (universal, ad-hoc signed unless CODESIGN_IDENTITY is set)
app:
	./scripts/build-app.sh direct

## Build and launch
run: app
	-pkill -x MacClipboard
	open $(APP)

## Install into /Applications and launch (needed for Launch at Login)
install: app
	-pkill -x MacClipboard
	rm -rf /Applications/MacClipboard.app
	cp -R $(APP) /Applications/
	open /Applications/MacClipboard.app

## Sandboxed Mac App Store build (see scripts/package-appstore.sh to make the .pkg)
appstore:
	./scripts/build-app.sh appstore

## Zip for GitHub Releases (notarized when NOTARY_PROFILE is set)
release:
	./scripts/release-github.sh

## Unit tests (needs Xcode; also run by GitHub Actions)
test:
	swift test

## Regenerate Resources/AppIcon.icns
icon:
	rm -rf build/AppIcon.iconset && mkdir -p build
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build build
