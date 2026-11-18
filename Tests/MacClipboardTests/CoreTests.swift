import AppKit
import CryptoKit
import XCTest
@testable import MacClipboard

final class ItemAnalyzerTests: XCTestCase {
    private func rep(_ type: String, _ string: String) -> PasteboardRepresentation {
        PasteboardRepresentation(type: type, data: Data(string.utf8))
    }

    func testPlainText() {
        let result = ItemAnalyzer.analyze([[rep(ItemAnalyzer.utf8Text, "hello world")]])
        XCTAssertEqual(result.item.kind, .text)
        XCTAssertEqual(result.item.preview, "hello world")
        XCTAssertEqual(result.item.textLength, 11)
        XCTAssertTrue(result.item.hasText)
    }

    func testVeryLongTextKeepsFullLengthButShortPreview() {
        let long = String(repeating: "abcdefghij", count: 1_000_000) // 10 MB
        let result = ItemAnalyzer.analyze([[rep(ItemAnalyzer.utf8Text, long)]])
        XCTAssertEqual(result.item.textLength, long.count)
        XCTAssertEqual(result.item.preview.count, ItemAnalyzer.previewCharacterLimit)
        XCTAssertEqual(result.item.byteCount, long.utf8.count)
    }

    func testSameTextHasSameHash() {
        let a = ItemAnalyzer.analyze([[rep(ItemAnalyzer.utf8Text, "same")]])
        let b = ItemAnalyzer.analyze([[rep(ItemAnalyzer.utf8Text, "same"), rep(ItemAnalyzer.rtf, "{\\rtf1 same}")]])
        let c = ItemAnalyzer.analyze([[rep(ItemAnalyzer.utf8Text, "different")]])
        XCTAssertEqual(a.item.contentHash, b.item.contentHash)
        XCTAssertNotEqual(a.item.contentHash, c.item.contentHash)
    }

    func testFiles() {
        let snapshot: PasteboardSnapshot = [
            [rep(ItemAnalyzer.fileURL, "file:///tmp/a.txt")],
            [rep(ItemAnalyzer.fileURL, "file:///tmp/b%20c.zip")],
        ]
        let result = ItemAnalyzer.analyze(snapshot)
        XCTAssertEqual(result.item.kind, .files)
        XCTAssertEqual(result.item.filePaths, ["/tmp/a.txt", "/tmp/b c.zip"])
        XCTAssertEqual(ItemAnalyzer.plainText(in: snapshot), "/tmp/a.txt\n/tmp/b c.zip")
    }

    func testImageThumbnail() throws {
        let png = try XCTUnwrap(Self.makePNG(width: 2000, height: 1000))
        let result = ItemAnalyzer.analyze([[PasteboardRepresentation(type: "public.png", data: png)]])
        XCTAssertEqual(result.item.kind, .image)
        XCTAssertEqual(result.item.pixelWidth, 2000)
        XCTAssertEqual(result.item.pixelHeight, 1000)
        let thumb = try XCTUnwrap(result.thumbnailPNG.flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertLessThanOrEqual(max(thumb.pixelsWide, thumb.pixelsHigh), ItemAnalyzer.thumbnailMaxPixels)
        XCTAssertFalse(result.item.hasText)
    }

    func testHTMLOnlyBecomesText() {
        let result = ItemAnalyzer.analyze([[rep(ItemAnalyzer.html, "<p>Hello <b>there</b> &amp; bye</p>")]])
        XCTAssertEqual(result.item.kind, .text)
        XCTAssertEqual(result.item.preview, "Hello there & bye")
    }

    func testSkipsDuplicateTextTypes() {
        XCTAssertTrue(ClipboardStore.shouldStore("public.utf8-plain-text", hasUTF8: true))
        XCTAssertFalse(ClipboardStore.shouldStore("public.utf16-plain-text", hasUTF8: true))
        XCTAssertFalse(ClipboardStore.shouldStore("NSStringPboardType", hasUTF8: true))
        XCTAssertFalse(ClipboardStore.shouldStore("dyn.ah62d4rv4gu8y", hasUTF8: false))
        XCTAssertTrue(ClipboardStore.shouldStore("public.png", hasUTF8: false))
    }

    static func makePNG(width: Int, height: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

final class HistoryStorageTests: XCTestCase {
    private var root: URL!
    private var cipher: HistoryCipher!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacClipboardTests-\(UUID().uuidString)")
        cipher = HistoryCipher(key: SymmetricKey(size: .bits256))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testRoundTripIsEncryptedAndPrivate() throws {
        let storage = HistoryStorage(root: root, cipher: cipher)
        let secret = "super secret clipboard text"
        let snapshot: PasteboardSnapshot = [[PasteboardRepresentation(type: ItemAnalyzer.utf8Text, data: Data(secret.utf8))]]
        var item = ItemAnalyzer.analyze(snapshot).item
        item.isPinned = true

        try storage.saveItem(item.id, snapshot: snapshot, thumbnailPNG: nil)
        try storage.saveIndex([item])

        // Reload through a fresh instance, as after a restart.
        let reloaded = HistoryStorage(root: root, cipher: cipher)
        let items = reloaded.loadAll()
        XCTAssertEqual(items.map(\.id), [item.id])
        XCTAssertTrue(items[0].isPinned)
        XCTAssertEqual(try reloaded.loadSnapshot(item.id), snapshot)

        // Nothing on disk contains the plaintext, and files are owner-only.
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? Int)
            XCTAssertEqual(permissions & 0o077, 0, "\(url.lastPathComponent) is readable by others")
            if attributes[.type] as? FileAttributeType == .typeRegular {
                let bytes = try Data(contentsOf: url)
                XCTAssertNil(bytes.range(of: Data(secret.utf8)), "\(url.lastPathComponent) contains plaintext")
            }
        }
    }

    func testWrongKeyCannotRead() throws {
        let storage = HistoryStorage(root: root, cipher: cipher)
        let snapshot: PasteboardSnapshot = [[PasteboardRepresentation(type: ItemAnalyzer.utf8Text, data: Data("x".utf8))]]
        let item = ItemAnalyzer.analyze(snapshot).item
        try storage.saveItem(item.id, snapshot: snapshot, thumbnailPNG: nil)
        try storage.saveIndex([item])

        let other = HistoryStorage(root: root, cipher: HistoryCipher(key: SymmetricKey(size: .bits256)))
        XCTAssertTrue(other.loadIndex().isEmpty)
        XCTAssertThrowsError(try other.loadSnapshot(item.id))
    }

    func testOrphansAndDeletes() throws {
        let storage = HistoryStorage(root: root, cipher: cipher)
        let snapshot: PasteboardSnapshot = [[PasteboardRepresentation(type: ItemAnalyzer.utf8Text, data: Data("a".utf8))]]
        let kept = ItemAnalyzer.analyze(snapshot).item
        let orphan = UUID()
        try storage.saveItem(kept.id, snapshot: snapshot, thumbnailPNG: nil)
        try storage.saveItem(orphan, snapshot: snapshot, thumbnailPNG: nil)
        try storage.saveIndex([kept])

        XCTAssertEqual(storage.loadAll().map(\.id), [kept.id])
        XCTAssertThrowsError(try storage.loadSnapshot(orphan))

        storage.deleteItem(kept.id)
        XCTAssertTrue(storage.loadAll().isEmpty)
    }
}

final class AppSettingsTests: XCTestCase {
    func testDefaultsAndValidation() throws {
        let suite = "MacClipboardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.historyLimit, AppSettings.defaultHistoryLimit)
        XCTAssertTrue(settings.keepAfterRestart)

        settings.historyLimit = 300
        XCTAssertEqual(AppSettings(defaults: defaults).historyLimit, 300)

        defaults.set(7, forKey: "historyLimit")
        XCTAssertEqual(AppSettings(defaults: defaults).historyLimit, AppSettings.defaultHistoryLimit)
    }
}
