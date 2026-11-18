# Security

Clipboard history often contains passwords, tokens, and private messages. MacClipboard is built to keep that data on your Mac, out of reach of other users, and unreadable if the disk or a backup is copied.

## How your data is handled

| | |
| --- | --- |
| **Where it's stored** | `~/Library/Application Support/MacClipboard/`. The Mac App Store build stores it inside its sandbox container instead. |
| **Encryption** | Every file, including the index of previews, is encrypted with AES-256-GCM (Apple CryptoKit). |
| **Key** | A random 256-bit key in your login Keychain. It is only available after you first unlock the Mac, is never synced to iCloud, and is never written to disk in the clear. |
| **File permissions** | The folder is `0700` and the files are `0600`, so other macOS user accounts can't read them. |
| **Backups** | The folder is excluded from Time Machine. |
| **Network** | None. The app makes no network connections, and the App Store build has no network entitlement. |
| **Password managers** | Copies marked concealed or transient (`org.nspasteboard.ConcealedType` and similar) are never recorded. Copies made while a known password manager is in front are also ignored; you can turn that off in Settings. |
| **Deleting** | Deleting an item removes its files. *Erase All History* in Settings removes everything, pinned items included. Turning off *Keep history after restart* deletes unpinned items when the app quits. |
| **Keychain unavailable** | If the key can't be read (for example, you denied Keychain access), history is kept for the current session only, using a throwaway key, and deleted when the app quits. |

## Permissions

- **Accessibility**: used only to send ⌘V to the app you're pasting into and, in the direct build, to find the text cursor so the panel opens next to it. The App Store build can't read other apps' UI at all.
- **Global shortcut**: registered with `RegisterEventHotKey`. The app does not log keystrokes and does not use an event tap.

## Reporting a vulnerability

Please report security issues privately through [GitHub Security Advisories](https://github.com/anil3a/macClipboard/security/advisories/new) rather than in a public issue.
