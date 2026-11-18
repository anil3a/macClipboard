import AppKit
import ApplicationServices
import Carbon

/// Everything that needs the Accessibility permission: simulating ⌘V and finding the text caret.
enum Accessibility {
    /// True for the Mac App Store build. The sandbox allows posting ⌘V but not reading other apps' UI.
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// Whether we may send ⌘V to other apps.
    static var canPaste: Bool { CGPreflightPostEventAccess() || AXIsProcessTrusted() }

    /// Whether we can ask other apps where their text caret is.
    static var canReadCaret: Bool { !isSandboxed && AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to System Settings › Privacy & Security › Accessibility.
    static func requestAccess() {
        if isSandboxed {
            _ = CGRequestPostEventAccess()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Paste

    /// Sends ⌘V to the frontmost app.
    static func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Ignore modifier keys the user may still be holding (e.g. Shift from ⇧⌘V).
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let key = keyCodeForV()
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// The physical key that produces "v" with ⌘ held in the current keyboard layout (handles Dvorak, AZERTY…).
    private static func keyCodeForV() -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        let commandModifier = UInt32((cmdKey >> 8) & 0xFF)
        let target = UniChar(("v" as Unicode.Scalar).value)

        return layoutData.withUnsafeBytes { raw -> CGKeyCode in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return fallback }
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDisplay), commandModifier,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState, chars.count, &length, &chars
                )
                if status == noErr, length == 1, chars[0] == target { return CGKeyCode(code) }
            }
            return fallback
        }
    }

    // MARK: Caret

    /// Screen rect (Cocoa coordinates) of the text caret in the focused app, if it exposes one.
    static func caretRect() -> NSRect? {
        guard canReadCaret else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.15)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.15)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                focused, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }

        // AX uses top-left origin relative to the primary screen; Cocoa uses bottom-left.
        guard let primary = NSScreen.screens.first else { return nil }
        let converted = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(converted.insetBy(dx: -1, dy: -1)) }) else { return nil }
        return converted
    }
}
