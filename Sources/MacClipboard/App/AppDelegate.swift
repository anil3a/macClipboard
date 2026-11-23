import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private lazy var store = ClipboardStore(settings: settings)
    private lazy var history = HistoryWindowController(store: store, settings: settings)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, store: store)
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        setupStatusItem()
        registerHotKey(settings.shortcut)
        settings.$shortcut
            .dropFirst()
            .sink { [weak self] shortcut in self?.registerHotKey(shortcut) }
            .store(in: &cancellables)

        if !Accessibility.canPaste {
            Accessibility.requestAccessOncePerLaunch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.prepareForTermination()
    }

    // MARK: Hotkey

    private func registerHotKey(_ shortcut: Shortcut) {
        hotKey = nil
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
            self?.history.toggle()
        }
        if hotKey == nil {
            NSLog("MacClipboard: could not register \(shortcut.title); another app may be using it.")
        }
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard history")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let show = item("Show Clipboard History", #selector(showHistory))
        show.keyEquivalent = "v"
        show.keyEquivalentModifierMask = settings.shortcut.cocoaModifiers
        menu.addItem(show)

        menu.addItem(.separator())

        let enabled = item("Save Clipboard History", #selector(toggleEnabled))
        enabled.state = settings.isEnabled ? .on : .off
        menu.addItem(enabled)

        let clear = item("Clear All (Keeps Pinned)", #selector(clearHistory))
        clear.isEnabled = store.hasUnpinnedItems
        menu.addItem(clear)

        if !Accessibility.canPaste {
            menu.addItem(.separator())
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccessibility)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit MacClipboard", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showHistory() {
        // Wait for the status menu to close first.
        DispatchQueue.main.async { self.history.show() }
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
    }

    @objc private func clearHistory() {
        store.clearUnpinned()
    }

    @objc private func grantAccessibility() {
        Accessibility.requestAccess()
        Accessibility.openSettings()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
