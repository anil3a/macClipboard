import AppKit
import Carbon
import SwiftUI

/// A borderless floating panel that takes keyboard input without activating our app,
/// so the app you were typing in stays frontmost and receives the paste.
final class HistoryPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

final class HistoryViewModel: ObservableObject {
    @Published var selectedID: UUID?
    /// Set only by keyboard navigation, so hovering doesn't make the list jump.
    @Published var scrollTarget: UUID?
    @Published var needsAccessibility = false
    /// Mouse position at the last keyboard move; hover is ignored until the mouse actually moves.
    var mouseLocationAtKeyboardMove: NSPoint?
}

final class HistoryWindowController: NSObject, NSWindowDelegate {
    static let panelSize = NSSize(width: 360, height: 460)

    private let store: ClipboardStore
    private let settings: AppSettings
    private let model = HistoryViewModel()
    private let panel = HistoryPanel(size: HistoryWindowController.panelSize)
    private var clickMonitor: Any?

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        super.init()

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 10)

        let root = HistoryView(
            store: store,
            settings: settings,
            model: model,
            onPaste: { [weak self] item, plain in self?.paste(item, plainTextOnly: plain) },
            onHoverItem: { [weak self] id in self?.hover(id) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        panel.contentView = effect
        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.needsAccessibility = !Accessibility.canPaste
        model.selectedID = store.items.first?.id
        model.scrollTarget = store.items.first?.id
        model.mouseLocationAtKeyboardMove = NSEvent.mouseLocation

        panel.setFrameOrigin(origin(for: Self.panelSize))
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.scrollTarget = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: Positioning

    /// Like Windows, open next to the text caret; fall back to the mouse pointer.
    private func origin(for size: NSSize) -> NSPoint {
        let anchor = Accessibility.caretRect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = 6

        var x = anchor.minX
        var y = anchor.minY - gap - size.height       // below the caret
        if y < visible.minY { y = anchor.maxY + gap }  // not enough room: above it

        x = min(max(x, visible.minX + gap), visible.maxX - size.width - gap)
        y = min(max(y, visible.minY + gap), visible.maxY - size.height - gap)
        return NSPoint(x: x, y: y)
    }

    // MARK: Actions

    private func paste(_ item: ClipboardItem, plainTextOnly: Bool) {
        hide()
        store.copyToPasteboard(item, plainTextOnly: plainTextOnly) { success in
            guard success else { NSSound.beep(); return }
            guard Accessibility.canPaste else {
                // Without permission we can only copy; the user presses ⌘V themselves.
                Accessibility.requestAccess()
                return
            }
            // Give the previous app a moment to get keyboard focus back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Accessibility.sendPaste()
            }
        }
    }

    private func hover(_ id: UUID) {
        if let location = model.mouseLocationAtKeyboardMove {
            guard location != NSEvent.mouseLocation else { return }
            model.mouseLocationAtKeyboardMove = nil
        }
        model.selectedID = id
    }

    private var selectedIndex: Int? {
        store.items.firstIndex { $0.id == model.selectedID }
    }

    private func select(index: Int) {
        let items = store.items
        guard !items.isEmpty else { model.selectedID = nil; return }
        let clamped = min(max(index, 0), items.count - 1)
        model.selectedID = items[clamped].id
        model.scrollTarget = items[clamped].id
        model.mouseLocationAtKeyboardMove = NSEvent.mouseLocation
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let items = store.items
        let current = selectedIndex
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
        case kVK_UpArrow:
            select(index: (current ?? 0) - 1)
        case kVK_DownArrow:
            select(index: current.map { $0 + 1 } ?? 0)
        case kVK_Home, kVK_PageUp:
            select(index: 0)
        case kVK_End, kVK_PageDown:
            select(index: items.count - 1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let current { paste(items[current], plainTextOnly: modifiers.contains(.shift) && items[current].hasText) }
        case kVK_Delete, kVK_ForwardDelete:
            if let current {
                store.delete(items[current].id)
                select(index: current)
            }
        case kVK_ANSI_P where modifiers.isEmpty || modifiers == .command:
            if let current { store.togglePin(items[current].id) }
        default:
            // Let ⌘-shortcuts etc. fall through, swallow everything else.
            return modifiers.contains(.command) ? false : true
        }
        return true
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
