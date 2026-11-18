import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Turns a raw pasteboard snapshot into a `ClipboardItem` (kind, preview, hash, thumbnail).
/// Safe to call from a background queue.
enum ItemAnalyzer {
    static let previewCharacterLimit = 3000
    static let thumbnailMaxPixels = 640

    struct Result {
        var item: ClipboardItem
        let thumbnailPNG: Data?
    }

    static let utf8Text = "public.utf8-plain-text"
    static let utf16Text = "public.utf16-plain-text"
    static let fileURL = "public.file-url"
    static let url = "public.url"
    static let rtf = "public.rtf"
    static let html = "public.html"
    static let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif"]

    static func analyze(_ snapshot: PasteboardSnapshot, id: UUID = UUID(), date: Date = Date()) -> Result {
        let first = snapshot.first ?? []
        let byteCount = snapshot.reduce(0) { $0 + $1.reduce(0) { $0 + $1.data.count } }

        func make(_ kind: ClipboardItem.Kind, preview: String, hashOf content: Data, filePaths: [String] = [],
                  textLength: Int? = nil, pixels: CGSize? = nil, hasText: Bool, thumbnail: Data? = nil) -> Result {
            var item = ClipboardItem(
                id: id, date: date, isPinned: false, kind: kind, preview: preview, filePaths: filePaths,
                textLength: textLength, pixelWidth: pixels.map { Int($0.width) }, pixelHeight: pixels.map { Int($0.height) },
                byteCount: byteCount, contentHash: hash(kind: kind, content), hasText: hasText
            )
            if let thumbnail { item.thumbnail = NSImage(data: thumbnail) }
            return Result(item: item, thumbnailPNG: thumbnail)
        }

        // Files copied in Finder (only references, so even huge files are cheap).
        let paths = fileURLs(in: snapshot).map(\.path)
        if !paths.isEmpty {
            let names = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: "\n")
            return make(.files, preview: names, hashOf: Data(paths.joined(separator: "\n").utf8), filePaths: paths, hasText: true)
        }

        // Text, any length.
        if let text = text(in: first) {
            return make(.text, preview: String(text.prefix(previewCharacterLimit)), hashOf: Data(text.utf8),
                        textLength: text.count, hasText: true)
        }

        // Images, e.g. screenshots.
        for type in imageTypes {
            if let data = data(type, in: first) {
                let thumb = thumbnail(from: data)
                return make(.image, preview: "Image", hashOf: data, pixels: thumb?.pixelSize, hasText: false, thumbnail: thumb?.png)
            }
        }

        let type = first.first?.type ?? "unknown"
        return make(.other, preview: type, hashOf: first.first?.data ?? Data(), hasText: false)
    }

    // MARK: Helpers

    static func data(_ type: String, in reps: [PasteboardRepresentation]) -> Data? {
        reps.first { $0.type == type }?.data
    }

    static func fileURLs(in snapshot: PasteboardSnapshot) -> [URL] {
        snapshot.compactMap { reps in
            guard let d = data(fileURL, in: reps), let s = String(data: d, encoding: .utf8) else { return nil }
            return URL(string: s)
        }
    }

    /// Best plain-text version of one pasteboard item.
    static func text(in reps: [PasteboardRepresentation]) -> String? {
        if let d = data(utf8Text, in: reps), let s = String(data: d, encoding: .utf8) { return s }
        if let d = data(utf16Text, in: reps), let s = String(data: d, encoding: .utf16LittleEndian) { return s }
        if let d = data(rtf, in: reps), let a = NSAttributedString(rtf: d, documentAttributes: nil) { return a.string }
        if let d = data(html, in: reps), let s = String(data: d, encoding: .utf8) { return stripHTML(s) }
        if let d = data(url, in: reps), let s = String(data: d, encoding: .utf8) { return s }
        return nil
    }

    /// Text used for "Paste as Plain Text": the text itself, or file paths.
    static func plainText(in snapshot: PasteboardSnapshot) -> String? {
        let paths = fileURLs(in: snapshot).map(\.path)
        if !paths.isEmpty { return paths.joined(separator: "\n") }
        return snapshot.first.flatMap(text(in:))
    }

    static func stripHTML(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<br\\s*/?>|</p>|</div>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&amp;": "&"] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hash(kind: ClipboardItem.Kind, _ content: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: content)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Downscaled PNG preview without decoding the full image into memory.
    static func thumbnail(from data: Data) -> (png: Data, pixelSize: CGSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (output as Data, CGSize(width: width, height: height))
    }
}
