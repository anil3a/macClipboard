import AppKit

/// One pasteboard type and its raw bytes.
struct PasteboardRepresentation: Codable, Equatable {
    let type: String
    let data: Data
}

/// Everything that was on the pasteboard: one array of representations per pasteboard item
/// (copying several files in Finder produces several items).
typealias PasteboardSnapshot = [[PasteboardRepresentation]]

/// Lightweight metadata for one history entry. The full pasteboard data lives encrypted on disk
/// and is only loaded when the entry is pasted, so hundreds of large items don't fill up memory.
struct ClipboardItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text, image, files, other
    }

    let id: UUID
    var date: Date
    var isPinned: Bool
    let kind: Kind
    /// Shortened text, file names, or the type name, for display.
    let preview: String
    let filePaths: [String]
    /// Full length of the text, when the item is text.
    let textLength: Int?
    let pixelWidth: Int?
    let pixelHeight: Int?
    /// Total size of all stored representations.
    let byteCount: Int
    /// SHA-256 of the content, used to spot duplicates.
    let contentHash: String
    /// Whether "Paste as Plain Text" can be offered.
    let hasText: Bool

    /// Small preview image (images only). Not part of the index; stored next to the item's data.
    var thumbnail: NSImage? = nil

    private enum CodingKeys: String, CodingKey {
        case id, date, isPinned, kind, preview, filePaths, textLength, pixelWidth, pixelHeight, byteCount, contentHash, hasText
    }
}
