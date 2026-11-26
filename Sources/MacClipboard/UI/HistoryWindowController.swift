import AppKit
import Carbon
import Combine
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
    @Published var query = ""
    /// The search field, so the controller can focus it when the panel opens.
    weak var searchField: NSSearchField?
    /// Mouse position at the last keyboard move; hover is ignored until the mouse actually moves.
    var mouseLocationAtKeyboardMove: NSPoint?
}

final class HistoryWindowController: NSObject, NSWindowDelegate {
    static let panelWidth: CGFloat = 360
    static let defaultPanelHeight: CGFloat = 540
    static let minPanelHeight: CGFloat = 300
    static let panelSize = NSSize(width: panelWidth, height: defaultPanelHeight)
    /// Space kept between the panel and the caret or the screen edges.
    private static let gap: CGFloat = 6

    private let store: ClipboardStore
    private let settings: AppSettings
    private let model = HistoryViewModel()
    private let panel = HistoryPanel(size: HistoryWindowController.panelSize)
    /// Panel frame and mouse position when a bottom-edge resize started.
    private var resizeStart: (frame: NSRect, mouseY: CGFloat)?
    private var clickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

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
            onHoverItem: { [weak self] id in self?.hover(id) },
            onResize: { [weak self] phase in self?.resize(phase) }
        )
        let hosting = NSHostingView(rootView: root)
        // The panel sets the size; SwiftUI just fills it (no size constraints fighting a resize).
        hosting.sizingOptions = []
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        panel.contentView = effect
        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }

        // Typing in the search box selects the first match.
        model.$query
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self else { return }
                let first = ClipboardItem.filter(self.store.items, query: query).first?.id
                self.model.selectedID = first
                self.model.scrollTarget = first
            }
            .store(in: &cancellables)
    }

    /// Items shown for the current search.
    private var visibleItems: [ClipboardItem] {
        ClipboardItem.filter(store.items, query: model.query)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.needsAccessibility = !Accessibility.canPaste
        model.query = ""
        model.selectedID = store.items.first?.id
        model.scrollTarget = store.items.first?.id
        model.mouseLocationAtKeyboardMove = NSEvent.mouseLocation

        panel.setFrame(initialFrame(), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        if let field = model.searchField { panel.makeFirstResponder(field) }

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
    /// Uses the height the user last dragged the panel to, if it fits on the screen.
    private func initialFrame() -> NSRect {
        let anchor = Accessibility.caretRect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap = Self.gap

        let saved = CGFloat(settings.panelHeight)
        let wanted = saved > 0 ? saved : Self.defaultPanelHeight
        let height = min(max(wanted, Self.minPanelHeight), visible.height - gap * 2)
        let size = NSSize(width: Self.panelWidth, height: height)

        var x = anchor.minX
        var y = anchor.minY - gap - size.height       // below the caret
        if y < visible.minY { y = anchor.maxY + gap }  // not enough room: above it

        x = min(max(x, visible.minX + gap), visible.maxX - size.width - gap)
        y = min(max(y, visible.minY + gap), visible.maxY - size.height - gap)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    /// Dragging the bottom edge: the top stays put and the bottom follows the mouse.
    private func resize(_ phase: ResizePhase) {
        let mouseY = NSEvent.mouseLocation.y
        switch phase {
        case .began:
            resizeStart = (panel.frame, mouseY)
        case .changed, .ended:
            guard let start = resizeStart else { return }
            let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? start.frame
            let top = start.frame.maxY
            let maxHeight = max(top - visible.minY - Self.gap, Self.minPanelHeight)
            let height = min(max(start.frame.height + (start.mouseY - mouseY), Self.minPanelHeight), maxHeight).rounded()
            if height != panel.frame.height {
                panel.setFrame(NSRect(x: start.frame.minX, y: top - height, width: start.frame.width, height: height), display: true)
                panel.invalidateShadow()
            }
            if phase == .ended {
                settings.panelHeight = Double(height)
                resizeStart = nil
            }
        }
    }

    // MARK: Actions

    private func paste(_ item: ClipboardItem, plainTextOnly: Bool) {
        hide()
        store.copyToPasteboard(item, plainTextOnly: plainTextOnly) { success in
            guard success else { NSSound.beep(); return }
            guard Accessibility.canPaste else {
                // Without permission we can only copy; the user presses ⌘V themselves.
                // The panel's banner explains this, so don't raise the system dialog on every paste.
                Accessibility.requestAccessOncePerLaunch()
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
        visibleItems.firstIndex { $0.id == model.selectedID }
    }

    private func select(index: Int) {
        let items = visibleItems
        guard !items.isEmpty else { model.selectedID = nil; return }
        let clamped = min(max(index, 0), items.count - 1)
        model.selectedID = items[clamped].id
        model.scrollTarget = items[clamped].id
        model.mouseLocationAtKeyboardMove = NSEvent.mouseLocation
    }

    /// Navigation keys are handled here before the search field sees them; everything else
    /// (letters, ⌫, ←/→) goes to the search field as normal typing.
    private func handleKey(_ event: NSEvent) -> Bool {
        let items = visibleItems
        let current = selectedIndex
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        switch Int(event.keyCode) {
        case kVK_Escape:
            if model.query.isEmpty { hide() } else { model.query = "" }
        case kVK_UpArrow:
            select(index: (current ?? 0) - 1)
        case kVK_DownArrow:
            select(index: current.map { $0 + 1 } ?? 0)
        case kVK_PageUp:
            select(index: 0)
        case kVK_PageDown:
            select(index: items.count - 1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let current { paste(items[current], plainTextOnly: modifiers.contains(.shift) && items[current].hasText) }
        case kVK_Delete where modifiers == .command, kVK_ForwardDelete where modifiers == .command:
            if let current {
                store.delete(items[current].id)
                select(index: current)
            }
        case kVK_ANSI_P where modifiers == .command:
            if let current { store.togglePin(items[current].id) }
        default:
            return handleEditingShortcut(event, modifiers: modifiers)
        }
        return true
    }

    /// This app has no Edit menu, so ⌘A/⌘C/⌘X/⌘V/⌘Z in the search field are routed by hand.
    private func handleEditingShortcut(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers == .command || modifiers == [.command, .shift] else { return false }
        let action: Selector?
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a": action = #selector(NSText.selectAll(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "z": action = modifiers.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        default: action = nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: panel)
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
