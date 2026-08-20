import AppKit
import Carbon.HIToolbox

enum HotKeyAction: Hashable {
    case togglePanel
    case openSite(UUID)
}

protocol HotKeyProviding: AnyObject {
    func register(action: HotKeyAction, combo: HotKeyCombo, handler: @escaping () -> Void)
    func unregister(action: HotKeyAction)
}

struct HotKeyCombo: Codable, Equatable, Hashable {
    /// Virtual key code (`kVK_*`).
    var keyCode: UInt16
    /// Raw value of `NSEvent.ModifierFlags` restricted to device-independent flags.
    var modifierFlags: UInt

    static let defaultToggle = HotKeyCombo(
        keyCode: UInt16(kVK_ANSI_E),
        modifierFlags: NSEvent.ModifierFlags.command.rawValue
    )

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    @MainActor var displayString: String {
        var parts = ""
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option) { parts += "⌥" }
        if flags.contains(.shift) { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }
        return parts + KeyCodeNames.name(for: keyCode)
    }
}

@MainActor
enum KeyCodeNames {
    private static let table: [UInt16: String] = [
        UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_Escape): "⎋", UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_ANSI_Grave): "`", UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[", UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\", UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_Comma): ",", UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/"
    ]

    static func name(for keyCode: UInt16) -> String {
        if let known = table[keyCode] { return known }
        if let character = Self.characterFromLayout(keyCode) { return character.uppercased() }
        return "Key \(keyCode)"
    }

    private static func characterFromLayout(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let keyLayout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return -1 }
            return UCKeyTranslate(
                keyLayout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

/// Zero-dependency global hotkey registration via Carbon's `RegisterEventHotKey`, which is the
/// sandbox- and App Store-safe API and needs no Accessibility permission.
final class HotKeyManager: HotKeyProviding {
    private struct Registration {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var actionIDs: [HotKeyAction: UInt32] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    static let shared = HotKeyManager()

    private init() {}

    func register(action: HotKeyAction, combo: HotKeyCombo, handler: @escaping () -> Void) {
        unregister(action: action)
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x534C4442), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        Diagnostics.trace("hotkey", "carbonRegister status=\(status) key=\(combo.keyCode)")
        guard status == noErr, let ref else {
            Diagnostics.panel.error(
                """
                event=hotKeyRegisterFailed keyCode=\(combo.keyCode, privacy: .public) \
                modifiers=\(combo.modifierFlags, privacy: .public) status=\(status, privacy: .public)
                """
            )
            return
        }
        registrations[id] = Registration(ref: ref, handler: handler)
        actionIDs[action] = id
    }

    func unregister(action: HotKeyAction) {
        guard let id = actionIDs.removeValue(forKey: action),
              let registration = registrations.removeValue(forKey: id)
        else { return }
        UnregisterEventHotKey(registration.ref)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                HotKeyManager.shared.handleHotKey(id: hotKeyID.id)
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard let registration = registrations[id] else { return }
        registration.handler()
    }
}
