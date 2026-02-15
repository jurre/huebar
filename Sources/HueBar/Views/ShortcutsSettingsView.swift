import SwiftUI

struct ShortcutsSettingsView: View {
    @Bindable var hotkeyManager: HotkeyManager
    var bridgeManager: BridgeManager

    @State private var isAdding = false
    @State private var selectedTargetId: String = ""
    @State private var recordedKeyCode: UInt32?
    @State private var recordedModifiers: UInt32?
    @State private var conflictWarning: String?

    private var targets: [(id: String, name: String, type: HotkeyBinding.TargetType)] {
        var result: [(id: String, name: String, type: HotkeyBinding.TargetType)] = []
        for bridge in bridgeManager.bridges {
            let client = bridge.client
            result += client.rooms.map { (id: $0.id, name: $0.name, type: HotkeyBinding.TargetType.room) }
            result += client.zones.map { (id: $0.id, name: $0.name, type: HotkeyBinding.TargetType.zone) }
        }
        return result
    }

    private var hasMultipleBridges: Bool {
        bridgeManager.bridges.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hotkeyManager.bindings.isEmpty && !isAdding {
                Text("No keyboard shortcuts configured.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            ForEach(hotkeyManager.bindings) { binding in
                HStack {
                    Text(binding.targetName)
                        .font(.body.weight(.medium))
                    Spacer()
                    KeyCapsView(parts: binding.displayParts)
                    Button {
                        hotkeyManager.removeBinding(binding)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isAdding {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Room / Zone", selection: $selectedTargetId) {
                        Text("Select…").tag("")
                        ForEach(Array(bridgeManager.bridges.enumerated()), id: \.element.id) { _, bridge in
                            let client = bridge.client
                            if hasMultipleBridges {
                                Section(bridge.name) {
                                    ForEach(client.rooms) { room in
                                        Text(room.name).tag(room.id)
                                    }
                                    ForEach(client.zones) { zone in
                                        Text(zone.name).tag(zone.id)
                                    }
                                }
                            } else {
                                ForEach(client.rooms) { room in
                                    Text(room.name).tag(room.id)
                                }
                                ForEach(client.zones) { zone in
                                    Text(zone.name).tag(zone.id)
                                }
                            }
                        }
                    }
                    .controlSize(.small)

                    HStack {
                        Text("Shortcut")
                            .font(.caption)
                        Spacer()
                        KeyRecorderView(
                            keyCode: recordedKeyCode,
                            modifierFlags: recordedModifiers
                        ) { keyCode, mods in
                            recordedKeyCode = keyCode
                            recordedModifiers = mods
                            checkConflict(keyCode: keyCode, modifierFlags: mods)
                        }
                        .frame(width: 120, height: 22)
                    }

                    if let conflictWarning {
                        Label(conflictWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    HStack {
                        Button("Cancel") {
                            resetAddFlow()
                        }
                        .controlSize(.small)
                        Spacer()
                        Button("Add") {
                            addBinding()
                        }
                        .controlSize(.small)
                        .disabled(!canAdd)
                    }
                }
            }

            Button {
                isAdding = true
                selectedTargetId = ""
                recordedKeyCode = nil
                recordedModifiers = nil
                hotkeyManager.startRecordingMode { [self] keyCode, mods in
                    recordedKeyCode = keyCode
                    recordedModifiers = mods
                    checkConflict(keyCode: keyCode, modifierFlags: mods)
                }
            } label: {
                Label("Add Shortcut", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(isAdding)
        }
    }

    private var canAdd: Bool {
        !selectedTargetId.isEmpty && recordedKeyCode != nil && recordedModifiers != nil
    }

    private func addBinding() {
        guard let target = targets.first(where: { $0.id == selectedTargetId }),
              let keyCode = recordedKeyCode,
              let mods = recordedModifiers else { return }

        let binding = HotkeyBinding(
            targetType: target.type,
            targetId: target.id,
            targetName: target.name,
            keyCode: keyCode,
            modifierFlags: mods
        )
        hotkeyManager.addBinding(binding)
        resetAddFlow()
    }

    private func resetAddFlow() {
        isAdding = false
        selectedTargetId = ""
        recordedKeyCode = nil
        recordedModifiers = nil
        conflictWarning = nil
        hotkeyManager.stopRecordingMode()
    }

    private func checkConflict(keyCode: UInt32, modifierFlags: UInt32) {
        // Check for conflicts — catches combos already used within HueBar
        if let name = hotkeyManager.hasInternalConflict(keyCode: keyCode, modifierFlags: modifierFlags) {
            conflictWarning = "Already used by \"\(name)\""
        } else {
            conflictWarning = nil
        }
    }
}

// MARK: - Keycap Display

private struct KeyCapsView: View {
    let parts: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.white.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    )
            }
        }
    }
}
