# MacClipboard

[![CI](https://github.com/anil3a/macClipboard/actions/workflows/ci.yml/badge.svg)](https://github.com/anil3a/macClipboard/actions/workflows/ci.yml)

A small macOS menu bar app that works like the Windows 11 clipboard history (Win+V).

Press **⇧⌘V** anywhere. A panel opens next to your text cursor with everything you've copied recently. Pick an item and it's pasted into the app you're using.

## Features

- **History of 20, 50, 100, 200 or 300 items** (set in Settings; pinned items don't count toward the limit). Copying the same thing again moves it to the top.
- **Survives restarts.** History is saved to disk, encrypted. You can turn this off.
- **Large copies.** Very long text (up to 256 MB per copy), screenshots and images, rich text, and files copied in Finder. Only small previews are kept in memory; the full content is loaded from disk when you paste.
- **Paste into anything**: click or press ↩. ⇧↩ pastes as plain text.
- **Pin** items you use often so they're never removed.
- **Clear all** keeps pinned items. **Erase All History** in Settings removes everything.
- **Opens at your text cursor**, or at the mouse pointer when the app doesn't report a cursor position.
- **Private by design.** The history is encrypted with AES-256, password-manager copies are skipped, and the app makes no network connections. See [SECURITY.md](SECURITY.md).

### Keyboard

| Key | Action |
| --- | --- |
| ⇧⌘V | Open or close the history (can be changed to ⌃⌘V or ⌥⌘V) |
| ↑ ↓ / Home End | Select an item |
| ↩ | Paste |
| ⇧↩ | Paste as plain text |
| P | Pin or unpin |
| ⌫ | Delete |
| Esc | Close |

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
make release      # zip for GitHub Releases (notarized if configured)
make icon         # regenerate the app icon
make clean
```

### From GitHub Releases

Download `MacClipboard-x.y.z.zip` from [Releases](https://github.com/anil3a/macClipboard/releases), unzip it, and move the app to Applications. Builds made without a Developer ID aren't notarized, so the first time you open it, right-click the app and choose **Open**.

### First launch

1. **Accessibility.** macOS asks for this permission. Turn MacClipboard on in **System Settings › Privacy & Security › Accessibility**. It's needed to paste into other apps. Without it, picking an item only copies it, and you press ⌘V yourself.
2. **Keychain.** The app creates its encryption key in your login Keychain. If you rebuild the app, macOS may ask whether the new build may use that key. Choose **Always Allow**.

> **Developing?** Locally built apps are ad-hoc signed, so macOS treats each rebuild as a new app and asks for the two permissions again. Sign with a stable certificate to avoid that. A free Apple Development certificate, or a self-signed "Code Signing" certificate made in Keychain Access, both work:
> ```sh
> CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" make install
> ```
> To clear a stale Accessibility entry: `tccutil reset Accessibility io.github.anil3a.MacClipboard`

## Distribution

### GitHub Releases

Push a tag and GitHub Actions builds the app, runs the tests, and attaches a zip to a new release:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

To publish a build that opens without Gatekeeper warnings, sign it with a **Developer ID Application** certificate and notarize it locally:

```sh
xcrun notarytool store-credentials macclipboard-notary --apple-id you@example.com --team-id TEAMID
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=macclipboard-notary make release
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

## License

[MIT](LICENSE)
