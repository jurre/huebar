import Testing
import Foundation
import AppKit
@testable import HueBar

@Suite("HotkeyBinding Tests")
struct HotkeyBindingTests {

    // MARK: - displayParts modifier symbols

    @Test("displayParts with command only shows ⌘")
    func displayPartsCommandOnly() {
        let binding = HotkeyBinding(
            targetType: .room, targetId: "r1", targetName: "Office",
            keyCode: 0x00, modifierFlags: HotkeyBinding.cmdKey
        )
        let modifiers = binding.displayParts.dropLast()
        #expect(Array(modifiers) == ["⌘"])
    }

    @Test("displayParts with all modifiers in correct order: ⌃⌥⇧⌘")
    func displayPartsAllModifiers() {
        let allFlags = HotkeyBinding.controlKey | HotkeyBinding.optionKey
            | HotkeyBinding.shiftKey | HotkeyBinding.cmdKey
        let binding = HotkeyBinding(
            targetType: .zone, targetId: "z1", targetName: "Upstairs",
            keyCode: 0x7A, modifierFlags: allFlags
        )
        let modifiers = binding.displayParts.dropLast()
        #expect(Array(modifiers) == ["⌃", "⌥", "⇧", "⌘"])
    }

    @Test("displayParts with shift+command shows ⇧⌘")
    func displayPartsShiftCommand() {
        let flags = HotkeyBinding.shiftKey | HotkeyBinding.cmdKey
        let binding = HotkeyBinding(
            targetType: .room, targetId: "r2", targetName: "Kitchen",
            keyCode: 0x31, modifierFlags: flags
        )
        let modifiers = binding.displayParts.dropLast()
        #expect(Array(modifiers) == ["⇧", "⌘"])
    }

    @Test("displayParts with no modifiers has only key string")
    func displayPartsNoModifiers() {
        let binding = HotkeyBinding(
            targetType: .room, targetId: "r3", targetName: "Bedroom",
            keyCode: 0x7A, modifierFlags: 0
        )
        #expect(binding.displayParts == ["F1"])
    }

    @Test("displayParts includes special key string for F1")
    func displayPartsSpecialKeyF1() {
        let binding = HotkeyBinding(
            targetType: .room, targetId: "r4", targetName: "Hall",
            keyCode: 0x7A, modifierFlags: HotkeyBinding.cmdKey
        )
        #expect(binding.displayParts.last == "F1")
    }

    @Test("displayString joins parts without separator")
    func displayStringJoined() {
        let flags = HotkeyBinding.cmdKey | HotkeyBinding.shiftKey
        let binding = HotkeyBinding(
            targetType: .room, targetId: "r5", targetName: "Den",
            keyCode: 0x7A, modifierFlags: flags
        )
        #expect(binding.displayString == "⇧⌘F1")
    }

    // MARK: - Modifier conversion round-trip

    @Test("carbonModifiers and cocoaModifiers round-trip")
    func modifierConversionRoundTrip() {
        let original: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let carbon = HotkeyBinding.carbonModifiers(from: original)
        let cocoa = HotkeyBinding.cocoaModifiers(from: carbon)
        #expect(cocoa.contains(.command))
        #expect(cocoa.contains(.shift))
        #expect(cocoa.contains(.option))
        #expect(cocoa.contains(.control))
    }

    @Test("carbonModifiers maps individual flags correctly")
    func carbonModifiersIndividual() {
        #expect(HotkeyBinding.carbonModifiers(from: .command) == HotkeyBinding.cmdKey)
        #expect(HotkeyBinding.carbonModifiers(from: .shift) == HotkeyBinding.shiftKey)
        #expect(HotkeyBinding.carbonModifiers(from: .option) == HotkeyBinding.optionKey)
        #expect(HotkeyBinding.carbonModifiers(from: .control) == HotkeyBinding.controlKey)
    }

    @Test("cocoaModifiers from zero returns empty flags")
    func cocoaModifiersEmpty() {
        let flags = HotkeyBinding.cocoaModifiers(from: 0)
        #expect(!flags.contains(.command))
        #expect(!flags.contains(.shift))
        #expect(!flags.contains(.option))
        #expect(!flags.contains(.control))
    }

    // MARK: - Codable round-trip

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = HotkeyBinding(
            targetType: .zone, targetId: "zone-abc", targetName: "Garden",
            keyCode: 0x63, modifierFlags: HotkeyBinding.cmdKey | HotkeyBinding.optionKey
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.targetType == original.targetType)
        #expect(decoded.targetId == original.targetId)
        #expect(decoded.targetName == original.targetName)
        #expect(decoded.keyCode == original.keyCode)
        #expect(decoded.modifierFlags == original.modifierFlags)
    }

    @Test("Equatable compares all fields")
    func equatableWorks() {
        let a = HotkeyBinding(
            id: UUID(), targetType: .room, targetId: "r1", targetName: "Room",
            keyCode: 0x00, modifierFlags: HotkeyBinding.cmdKey
        )
        let b = HotkeyBinding(
            id: a.id, targetType: .room, targetId: "r1", targetName: "Room",
            keyCode: 0x00, modifierFlags: HotkeyBinding.cmdKey
        )
        #expect(a == b)
    }

    // MARK: - TargetType raw values

    @Test("TargetType raw values are stable strings")
    func targetTypeRawValues() {
        #expect(HotkeyBinding.TargetType.room.rawValue == "room")
        #expect(HotkeyBinding.TargetType.zone.rawValue == "zone")
    }
}
