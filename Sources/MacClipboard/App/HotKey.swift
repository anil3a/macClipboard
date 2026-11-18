import AppKit
import Carbon

/// A system-wide keyboard shortcut via Carbon's RegisterEventHotKey (needs no special permissions).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, &handlerRef) == noErr else {
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D43_4C50), id: 1) // "MCLP"
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// The shortcut choices offered in the menu. (Windows uses Win+V; on a Mac Cmd+V is plain paste,
/// so we default to Shift+Cmd+V.)
enum Shortcut: String, CaseIterable {
    case shiftCommandV, controlCommandV, optionCommandV

    var title: String {
        switch self {
        case .shiftCommandV: return "⇧⌘V"
        case .controlCommandV: return "⌃⌘V"
        case .optionCommandV: return "⌥⌘V"
        }
    }

    var keyCode: UInt32 { UInt32(kVK_ANSI_V) }

    var carbonModifiers: UInt32 {
        switch self {
        case .shiftCommandV: return UInt32(cmdKey | shiftKey)
        case .controlCommandV: return UInt32(cmdKey | controlKey)
        case .optionCommandV: return UInt32(cmdKey | optionKey)
        }
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        switch self {
        case .shiftCommandV: return [.command, .shift]
        case .controlCommandV: return [.command, .control]
        case .optionCommandV: return [.command, .option]
        }
    }
}
