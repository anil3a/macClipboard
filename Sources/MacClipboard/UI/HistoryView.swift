import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: HistoryViewModel
    let onPaste: (ClipboardItem, Bool) -> Void
    let onHoverItem: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.needsAccessibility { accessibilityBanner }
            Group {
                if !settings.isEnabled && store.items.isEmpty {
                    placeholder(
                        title: "Clipboard history is off",
                        message: "Turn it on to keep a list of the things you copy, so you can paste them later.",
                        button: ("Turn on", { settings.isEnabled = true })
                    )
                } else if store.items.isEmpty {
                    placeholder(
                        title: "Nothing here yet",
                        message: "Copy text, images or files and they'll show up here.",
                        button: nil
                    )
                } else {
                    list
                }
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .frame(width: HistoryWindowController.panelSize.width, height: HistoryWindowController.panelSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text("Clipboard history")
                .font(.system(size: 13, weight: .semibold))
            if !settings.isEnabled {
                Text("Paused")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
            }
            Spacer()
            Button("Clear all") { store.clearUnpinned() }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .disabled(!store.hasUnpinnedItems)
                .help("Remove everything except pinned items")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var accessibilityBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("Allow Accessibility access so items paste automatically. Until then, picking an item only copies it.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") { Accessibility.openSettings() }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.12)))
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.items) { item in
                        ClipboardItemCard(
                            item: item,
                            isSelected: item.id == model.selectedID,
                            onHover: { onHoverItem(item.id) },
                            onPaste: { plain in onPaste(item, plain) },
                            onTogglePin: { store.togglePin(item.id) },
                            onDelete: { store.delete(item.id) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onChange(of: model.scrollTarget) { target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(target) }
            }
        }
    }

    private var footer: some View {
        Text("↑↓ select   ↩ paste   ⇧↩ paste as text   P pin   ⌫ delete")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    private func placeholder(title: String, message: String, button: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let button {
                Button(button.0, action: button.1).padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
    }
}

struct ClipboardItemCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onHover: () -> Void
    let onPaste: (Bool) -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                ClipboardItemContent(item: item)
                if let caption = Self.caption(for: item) {
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                if isSelected || item.isPinned {
                    iconButton(item.isPinned ? "pin.fill" : "pin", help: item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
                }
                if isSelected {
                    iconButton("trash", help: "Delete", action: onDelete)
                }
            }
            .frame(width: 24)
        }
        .padding(.vertical, 9)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .background(shape.fill(Color.primary.opacity(isSelected ? 0.11 : 0.05)))
        .overlay(shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 1))
        .contentShape(shape)
        .onHover { inside in if inside { onHover() } }
        .onTapGesture { onPaste(false) }
        .contextMenu {
            Button("Paste") { onPaste(false) }
            Button("Paste as Plain Text") { onPaste(true) }
                .disabled(!item.hasText)
            Divider()
            Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
            Button("Delete", action: onDelete)
        }
    }

    /// Extra detail for big items: image dimensions, or the length of long text.
    private static func caption(for item: ClipboardItem) -> String? {
        let size = ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
        switch item.kind {
        case .image:
            if let w = item.pixelWidth, let h = item.pixelHeight, w > 0 { return "\(w) × \(h) · \(size)" }
            return size
        case .text:
            guard let length = item.textLength, length > ItemAnalyzer.previewCharacterLimit / 6 else { return nil }
            return "\(length.formatted()) characters · \(size)"
        case .files:
            return item.filePaths.count > 1 ? "\(item.filePaths.count) files" : nil
        case .other:
            return size
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

struct ClipboardItemContent: View {
    let item: ClipboardItem

    var body: some View {
        switch item.kind {
        case .text:
            Text(Self.preview(item.preview))
                .font(.system(size: 12.5))
                .lineLimit(5)
                .multilineTextAlignment(.leading)

        case .image:
            if let image = item.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: max(image.size.width, 1), maxHeight: min(max(image.size.height, 1), 110))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Label("Image", systemImage: "photo").font(.system(size: 12.5))
            }

        case .files:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.filePaths.prefix(4), id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if item.filePaths.count > 4 {
                    Text("+\(item.filePaths.count - 4) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

        case .other:
            Text("Unsupported content (\(item.preview))")
                .font(.system(size: 12))
                .italic()
                .foregroundStyle(.secondary)
        }
    }

    private static func preview(_ text: String) -> String {
        // Only the start is shown; skip leading blank lines so the card isn't empty.
        let trimmed = text.prefix(600).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(blank)" }
        return trimmed.replacingOccurrences(of: "\t", with: "    ")
    }
}
