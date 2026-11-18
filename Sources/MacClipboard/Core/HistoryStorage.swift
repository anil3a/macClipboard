import AppKit

/// Encrypted on-disk store for the clipboard history.
///
///     <root>/                      0700, excluded from Time Machine
///       index.enc                  encrypted JSON list of ClipboardItem metadata
///       items/<uuid>/data.enc      encrypted pasteboard snapshot
///       items/<uuid>/thumb.enc     encrypted PNG thumbnail (images only)
///
/// Not thread-safe: the store calls it from one serial queue.
final class HistoryStorage {
    let root: URL
    private let cipher: HistoryCipher
    private let fileManager = FileManager.default

    private var indexURL: URL { root.appendingPathComponent("index.enc") }
    private var itemsURL: URL { root.appendingPathComponent("items", isDirectory: true) }

    static func defaultRoot() -> URL {
        // Inside the sandbox this resolves to the app's private container automatically.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacClipboard", isDirectory: true)
    }

    init(root: URL, cipher: HistoryCipher) {
        self.root = root
        self.cipher = cipher
        prepareDirectories()
    }

    private func prepareDirectories() {
        for dir in [root, itemsURL] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var rootURL = root
        try? rootURL.setResourceValues(values)

        // Version 1.0 development builds kept pinned items unencrypted here.
        try? fileManager.removeItem(at: root.appendingPathComponent("pinned.plist"))
    }

    private func directory(for id: UUID) -> URL {
        itemsURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    // MARK: Index

    func loadIndex() -> [ClipboardItem] {
        guard let sealed = try? Data(contentsOf: indexURL) else { return [] }
        do {
            return try JSONDecoder().decode([ClipboardItem].self, from: try cipher.open(sealed))
        } catch {
            NSLog("MacClipboard: could not read history index: \(error)")
            return []
        }
    }

    func saveIndex(_ items: [ClipboardItem]) throws {
        try writeEncrypted(try JSONEncoder().encode(items), to: indexURL)
    }

    /// Loads the index with thumbnails, dropping entries whose data is missing
    /// and deleting data that no entry refers to.
    func loadAll() -> [ClipboardItem] {
        var items = loadIndex().filter { fileManager.fileExists(atPath: directory(for: $0.id).appendingPathComponent("data.enc").path) }
        for index in items.indices where items[index].kind == .image {
            if let png = try? readEncrypted(directory(for: items[index].id).appendingPathComponent("thumb.enc")) {
                items[index].thumbnail = NSImage(data: png)
            }
        }
        removeOrphans(keeping: Set(items.map(\.id)))
        return items
    }

    // MARK: Items

    func saveItem(_ id: UUID, snapshot: PasteboardSnapshot, thumbnailPNG: Data?) throws {
        let dir = directory(for: id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try writeEncrypted(try encoder.encode(snapshot), to: dir.appendingPathComponent("data.enc"))
        if let thumbnailPNG {
            try writeEncrypted(thumbnailPNG, to: dir.appendingPathComponent("thumb.enc"))
        }
    }

    func loadSnapshot(_ id: UUID) throws -> PasteboardSnapshot {
        let data = try readEncrypted(directory(for: id).appendingPathComponent("data.enc"))
        return try PropertyListDecoder().decode(PasteboardSnapshot.self, from: data)
    }

    func deleteItem(_ id: UUID) {
        try? fileManager.removeItem(at: directory(for: id))
    }

    func removeOrphans(keeping ids: Set<UUID>) {
        guard let dirs = try? fileManager.contentsOfDirectory(at: itemsURL, includingPropertiesForKeys: nil) else { return }
        for dir in dirs where UUID(uuidString: dir.lastPathComponent).map({ !ids.contains($0) }) ?? true {
            try? fileManager.removeItem(at: dir)
        }
    }

    /// Removes the whole store (used for the temporary, session-only store).
    func destroy() {
        try? fileManager.removeItem(at: root)
    }

    func diskUsage() -> Int {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
        }
        return total
    }

    // MARK: Encrypted file IO

    private func writeEncrypted(_ plaintext: Data, to url: URL) throws {
        try cipher.seal(plaintext).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func readEncrypted(_ url: URL) throws -> Data {
        try cipher.open(try Data(contentsOf: url, options: .mappedIfSafe))
    }
}
