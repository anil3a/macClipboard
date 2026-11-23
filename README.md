# MacClipboard

[![CI](https://github.com/anil3a/macClipboard/actions/workflows/ci.yml/badge.svg)](https://github.com/anil3a/macClipboard/actions/workflows/ci.yml)

A small macOS menu bar app that works like the Windows 11 clipboard history (Win+V).

Press **⇧⌘V** anywhere. A panel opens next to your text cursor with everything you've copied recently. Pick an item and it's pasted into the app you're using.

## Features

- **History of 20, 50, 100, 200 or 300 items** (set in Settings; pinned items don't count toward the limit). Copying the same thing again moves it to the top.
- **Survives restarts.** History is saved to disk, encrypted. You can turn this off.
- **Large copies.** Very long text (up to 256 MB per copy), screenshots and images, rich text, and files copied in Finder. Only small previews are kept in memory; the full content is loaded from disk when you paste.
- **Search.** Just start typing when the panel opens, or click the search box. Every word you type must match (case- and accent-insensitive). It searches text (the first 3,000 characters of each item), file names and paths, and "image" / "screenshot".
- **Paste into anything**: click or press ↩. ⇧↩, or the **Aa** button on the selected item, pastes as plain text.
- **Pin** items you use often so they're never removed.
- **Clear all** keeps pinned items. **Erase All History** in Settings removes everything.
- **Opens at your text cursor**, or at the mouse pointer when the app doesn't report a cursor position.
- **Private by design.** The history is encrypted with AES-256, password-manager copies are skipped, and the app makes no network connections. See [SECURITY.md](SECURITY.md).

### Keyboard

| Key | Action |
| --- | --- |
| ⇧⌘V | Open or close the history (can be changed to ⌃⌘V or ⌥⌘V) |
| *type* | Search |
| ↑ ↓ / Page Up Page Down | Select an item |
| ↩ | Paste |
| ⇧↩ | Paste as plain text |
| ⌘P | Pin or unpin |
| ⌘⌫ | Delete |
| Esc | Clear the search, or close |

Right-click an item for the same actions.

### Settings

Open **Settings…** from the menu bar icon (⌘,):

- Save clipboard history (on/off)
- History size: 20 / 50 / 100 / 200 / 300
- Keep history after restart
- Shortcut
- Launch at login
- Ignore copies from password managers
- Storage used, and Erase All History
- Accessibility permission status

## Install

### From source

Requires macOS 13 or later and either Xcode or just the Command Line Tools (`xcode-select --install`).

```sh
git clone git@github.com:anil3a/macClipboard.git
cd macClipboard
make install      # builds a universal app, copies it to /Applications and opens it
```

Other targets:

```sh
make run          # build and run from ./build
make test         # unit tests (needs Xcode; CI also runs them)
make appstore     # sandboxed Mac App Store build
make release      # build the downloadable .dmg and .zip into ./build
make publish      # build, tag v<version>, push, and create the GitHub Release
make icon         # regenerate the app icon
make clean
```

### Download

Get the latest **MacClipboard-x.y.z.dmg** from [Releases](https://github.com/anil3a/macClipboard/releases). Open it and drag **MacClipboard** into **Applications**. It's a universal app, so it runs on Apple silicon and Intel Macs.

Releases are signed by Anil Prajapati Newa with a self-signed certificate, and aren't notarized by Apple. The first time you open the app, macOS says it can't verify the developer. Go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. Or run:

```sh
xattr -dr com.apple.quarantine /Applications/MacClipboard.app
```

Check the download against `MacClipboard-x.y.z.sha256` with `shasum -a 256 -c MacClipboard-x.y.z.sha256`.

### First launch

1. **Accessibility.** macOS asks for this permission. Turn MacClipboard on in **System Settings › Privacy & Security › Accessibility**. It's needed to paste into other apps. Without it, picking an item only copies it, and you press ⌘V yourself.
2. **Keychain.** The app creates its encryption key in your login Keychain. If you rebuild the app, macOS may ask whether the new build may use that key. Choose **Always Allow**.

### Code signing

Builds are signed with the identity named in `CODESIGN_IDENTITY`. If that isn't set, the name in a local `.codesign-identity` file is used (that file isn't committed). If neither exists, the build is ad-hoc signed.

An ad-hoc build is a "new app" to macOS every time you rebuild, so it asks for Accessibility and Keychain access again. Signing with your own certificate keeps those permissions. A self-signed **Code Signing** certificate from Keychain Access (Certificate Assistant › Create a Certificate…) works:

```sh
echo "Your Certificate Name" > .codesign-identity
make install
```

The first time, macOS asks whether `codesign` may use the key. Choose **Always Allow**.
To clear a stale Accessibility entry: `tccutil reset Accessibility io.github.anil3a.MacClipboard`

## Distribution

### GitHub Releases

Releases are built and uploaded from your Mac with the [GitHub CLI](https://cli.github.com) (`gh auth login` once):

1. Set the new version in `Resources/Info.plist` (`CFBundleShortVersionString`) and commit it.
2. Run `make publish`.

It builds a signed universal app, makes the `.dmg`, `.zip` and SHA-256 checksums, creates and pushes the tag `v<version>`, and publishes the GitHub Release with install notes. (`.github/workflows/release.yml` can do the same from a tag push if GitHub Actions minutes are available.)

To publish a build that opens on any Mac without warnings, sign it with a **Developer ID Application** certificate ($99/year Apple Developer Program) and notarize it:

```sh
xcrun notarytool store-credentials macclipboard-notary --apple-id you@example.com --team-id TEAMID
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=macclipboard-notary make publish
```

### Mac App Store

The `appstore` flavor is sandboxed and ships with a privacy manifest. It declares no network access, no tracking, and no data collection.

1. In your Apple Developer account, register the bundle ID `io.github.anil3a.MacClipboard` (or set `BUNDLE_ID=...`), create a **Mac App Store** provisioning profile, and get **Apple Distribution** and **Mac Installer Distribution** certificates.
2. Build the package:
   ```sh
   CODESIGN_IDENTITY="Apple Distribution: Your Name (TEAMID)" \
   INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)" \
   TEAM_ID=TEAMID PROVISIONING_PROFILE=path/to/profile.provisionprofile \
     scripts/package-appstore.sh
   ```
3. Upload `build/MacClipboard-AppStore.pkg` with Apple's **Transporter** app.

In the App Store build, the sandbox doesn't allow reading other apps' text cursor position, so the panel opens at the mouse pointer. Pasting still works once Accessibility is allowed. In App Review notes, explain that Accessibility is used only to paste the item the user chose.

## How it works

```
Sources/MacClipboard/
  App/
    main.swift, AppDelegate.swift   menu bar app and menu
    AppSettings.swift               preferences (UserDefaults)
    ClipboardStore.swift            watches NSPasteboard, dedupes, enforces the limit, pins
    HotKey.swift                    global shortcut via Carbon RegisterEventHotKey
    Accessibility.swift             sends ⌘V (keyboard-layout aware) and finds the text cursor
  Core/
    ClipboardItem.swift             metadata kept in memory
    ItemAnalyzer.swift              preview, SHA-256 dedupe hash, image thumbnails (ImageIO)
    Encryption.swift                AES-GCM cipher and Keychain key storage
    HistoryStorage.swift            encrypted on-disk store (index + one folder per item)
  UI/
    HistoryWindowController.swift   floating non-activating panel and keyboard handling
    HistoryView.swift               the Windows-style list (SwiftUI)
    SettingsView.swift              Settings window
```

The pasteboard is checked every 0.4 s, which is cheap because only `changeCount` is compared. A new copy is read on the main thread. Hashing, thumbnail generation, encryption and disk writes happen on a background queue. The panel is a non-activating `NSPanel`, so the app you were typing in stays in front and receives the paste.

## Differences from Windows

- The shortcut is ⇧⌘V instead of Win+V, because ⌘V is plain paste on a Mac. This takes over "Paste and Match Style" in apps that use ⇧⌘V. Switch to ⌃⌘V in Settings if you need that.
- There are no emoji, GIF or cloud-sync tabs.
- Copying files in Finder stores a reference to the files, not their contents (as on Windows). Pasting works as long as the files still exist.

## Author

Made by **Anil Prajapati Newa** ([@anil3a](https://github.com/anil3a)).

## License

[MIT](LICENSE) © 2026 Anil Prajapati Newa
