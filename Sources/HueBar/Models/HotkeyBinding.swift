import AppKit
import Carbon.HIToolbox

struct HotkeyBinding: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var targetType: TargetType
    var targetId: String
    var targetName: String
    var keyCode: UInt32
    var modifierFlags: UInt32

    enum TargetType: String, Codable, Sendable {
        case room
        case zone
    }

    // MARK: - Carbon modifier masks

    static let cmdKey: UInt32 = 0x0100
    static let shiftKey: UInt32 = 0x0200
    static let optionKey: UInt32 = 0x0800
    static let controlKey: UInt32 = 0x1000

    // MARK: - Display

    var displayString: String {
        displayParts.joined()
    }

    /// Individual key symbols for keycap-style display.
    var displayParts: [String] {
        var parts: [String] = []
        if modifierFlags & Self.controlKey != 0 { parts.append("⌃") }
        if modifierFlags & Self.optionKey != 0 { parts.append("⌥") }
        if modifierFlags & Self.shiftKey != 0 { parts.append("⇧") }
        if modifierFlags & Self.cmdKey != 0 { parts.append("⌘") }
        parts.append(Self.stringForKeyCode(keyCode))
        return parts
    }

    // MARK: - Modifier conversion

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        return carbon
    }

    static func cocoaModifiers(from carbonFlags: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonFlags & cmdKey != 0 { flags.insert(.command) }
        if carbonFlags & shiftKey != 0 { flags.insert(.shift) }
        if carbonFlags & optionKey != 0 { flags.insert(.option) }
        if carbonFlags & controlKey != 0 { flags.insert(.control) }
        return flags
    }

    // MARK: - Key code to string

    /// Special keys that UCKeyTranslate doesn't handle well.
    private static let specialKeys: [UInt32: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
        0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
        0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]

    private static func stringForKeyCode(_ keyCode: UInt32) -> String {
        if let special = specialKeys[keyCode] { return special }

        // Use UCKeyTranslate to get the character for the current keyboard layout
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return "Key(\(keyCode))"
        }

        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let keyboardLayout = unsafeBitCast(
            CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self
        )

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0, // No modifiers for display
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else { return "Key(\(keyCode))" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
