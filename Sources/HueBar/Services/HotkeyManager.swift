import Carbon.HIToolbox
import Foundation

/// C callback for Carbon hotkey events — cannot capture context, uses static reference.
private func carbonHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
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

    if let manager = HotkeyManager.shared {
        let idValue = hotKeyID.id
        MainActor.assumeIsolated {
            if let bindingID = manager.hotKeyIDToBindingID[idValue],
               let binding = manager.bindings.first(where: { $0.id == bindingID })
            {
                if let recordingCallback = manager.onHotkeyRecorded {
                    // Recording mode: report the combo instead of triggering action
                    recordingCallback(binding.keyCode, binding.modifierFlags)
                } else {
                    manager.onHotkeyTriggered?(binding)
                }
            }
        }
    }

    return noErr
}

@Observable
@MainActor
final class HotkeyManager {
    // SAFETY: Set once during app init on the main thread, then only read from the
    // Carbon event C callback which also runs on the main thread.
    nonisolated(unsafe) static var shared: HotkeyManager?

    private static let userDefaultsKey = "hotkeyBindings"
    private static let hotKeySignature: FourCharCode = {
        let chars: [UInt8] = [
            UInt8(ascii: "H"), UInt8(ascii: "B"), UInt8(ascii: "a"), UInt8(ascii: "r"),
        ]
        return FourCharCode(chars[0]) << 24
            | FourCharCode(chars[1]) << 16
            | FourCharCode(chars[2]) << 8
            | FourCharCode(chars[3])
    }()

    var bindings: [HotkeyBinding] = []
    var onHotkeyTriggered: ((HotkeyBinding) -> Void)?

    /// When set, hotkey presses report the combo here instead of triggering actions.
    var onHotkeyRecorded: ((UInt32, UInt32) -> Void)?

    /// Maps Carbon EventHotKeyID.id → HotkeyBinding.id
    private(set) var hotKeyIDToBindingID: [UInt32: UUID] = [:]

    // SAFETY: Only accessed from @MainActor methods and the Carbon C callback
    // (which runs on the main thread), so there is no concurrent mutation.
    @ObservationIgnored
    private nonisolated(unsafe) var registeredHotKeys: [EventHotKeyRef?] = []
    private var nextHotKeyID: UInt32 = 1
    // SAFETY: Only accessed from @MainActor methods and the Carbon C callback
    // (which runs on the main thread), so there is no concurrent mutation.
    @ObservationIgnored
    private nonisolated(unsafe) var eventHandlerRef: EventHandlerRef?

    init() {
        Self.shared = self
        installCarbonHandler()
        loadBindings()
        registerAll()
    }

    deinit {
        // Carbon hotkey refs are not actor-isolated; safe to clean up here
        for ref in registeredHotKeys {
            if let ref { UnregisterEventHotKey(ref) }
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
        Self.shared = nil
    }

    // MARK: - Persistence

    func loadBindings() {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let decoded = try? JSONDecoder().decode([HotkeyBinding].self, from: data)
        else {
            bindings = []
            return
        }
        bindings = decoded
    }

    func saveBindings() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    // MARK: - Add / Remove

    func addBinding(_ binding: HotkeyBinding) {
        bindings.append(binding)
        saveBindings()
        registerHotKey(for: binding)
    }

    func removeBinding(_ binding: HotkeyBinding) {
        if let index = bindings.firstIndex(where: { $0.id == binding.id }) {
            bindings.remove(at: index)
        }
        saveBindings()
        // Re-register all since indices shift
        unregisterAll()
        registerAll()
    }

    // MARK: - Recording Mode

    /// Enter recording mode: existing hotkeys report their combo instead of triggering actions.
    func startRecordingMode(onRecorded: @escaping (UInt32, UInt32) -> Void) {
        onHotkeyRecorded = onRecorded
    }

    func stopRecordingMode() {
        onHotkeyRecorded = nil
    }

    // MARK: - Conflict Detection

    /// Check if a key combo conflicts with an existing HueBar binding.
    func hasInternalConflict(keyCode: UInt32, modifierFlags: UInt32) -> String? {
        if let existing = bindings.first(where: { $0.keyCode == keyCode && $0.modifierFlags == modifierFlags }) {
            return existing.targetName
        }
        return nil
    }

    // MARK: - Carbon Registration

    func registerAll() {
        for binding in bindings {
            registerHotKey(for: binding)
        }
    }

    func unregisterAll() {
        for ref in registeredHotKeys {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        registeredHotKeys.removeAll()
        hotKeyIDToBindingID.removeAll()
        nextHotKeyID = 1
    }

    private func registerHotKey(for binding: HotkeyBinding) {
        let id = nextHotKeyID
        nextHotKeyID += 1

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.hotKeySignature
        hotKeyID.id = id

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            registeredHotKeys.append(ref)
            hotKeyIDToBindingID[id] = binding.id
        }
    }

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }
}
