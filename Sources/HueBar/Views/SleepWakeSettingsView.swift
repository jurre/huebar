import SwiftUI

struct SleepWakeSettingsView: View {
    @Bindable var sleepWakeManager: SleepWakeManager
    var bridgeManager: BridgeManager

    @State private var isAdding = false
    @State private var selectedTargetId: String = ""
    @State private var selectedMode: SleepWakeMode = .both
    @State private var selectedSceneId: String = ""

    private var scenesForSelected: [HueScene] {
        guard !selectedTargetId.isEmpty else { return [] }
        for bridge in bridgeManager.bridges {
            let scenes = bridge.client.scenes(for: selectedTargetId)
            if !scenes.isEmpty { return scenes }
        }
        return []
    }

    private var canAdd: Bool {
        !selectedTargetId.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sleepWakeManager.configs.isEmpty && !isAdding {
                Text("No sleep/wake rules configured.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            ForEach(sleepWakeManager.configs) { config in
                HStack {
                    Text(config.targetName)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(config.mode.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.1))
                        .clipShape(Capsule())
                    if let sceneName = config.wakeSceneName {
                        Text(sceneName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        sleepWakeManager.remove(id: config.id)
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
                            let existing = Set(sleepWakeManager.configs.map(\.targetId))
                            let rooms = client.rooms.filter { !existing.contains($0.id) }
                            let zones = client.zones.filter { !existing.contains($0.id) }
                            if bridgeManager.bridges.count > 1 {
                                Section(bridge.name) {
                                    ForEach(rooms) { room in
                                        Text(room.name).tag(room.id)
                                    }
                                    ForEach(zones) { zone in
                                        Text(zone.name).tag(zone.id)
                                    }
                                }
                            } else {
                                ForEach(rooms) { room in
                                    Text(room.name).tag(room.id)
                                }
                                ForEach(zones) { zone in
                                    Text(zone.name).tag(zone.id)
                                }
                            }
                        }
                    }
                    .controlSize(.small)

                    Picker("Mode", selection: $selectedMode) {
                        Text("Sleep").tag(SleepWakeMode.sleepOnly)
                        Text("Wake").tag(SleepWakeMode.wakeOnly)
                        Text("Both").tag(SleepWakeMode.both)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    if selectedMode == .wakeOnly || selectedMode == .both {
                        Picker("Scene on Wake", selection: $selectedSceneId) {
                            Text("Default (turn on)").tag("")
                            ForEach(scenesForSelected) { scene in
                                Text(scene.name).tag(scene.id)
                            }
                        }
                        .controlSize(.small)
                    }

                    HStack {
                        Button("Cancel") {
                            resetAddFlow()
                        }
                        .controlSize(.small)
                        Spacer()
                        Button("Add") {
                            addConfig()
                        }
                        .controlSize(.small)
                        .disabled(!canAdd)
                    }
                }
            }

            Button {
                isAdding = true
                selectedTargetId = ""
                selectedMode = .both
                selectedSceneId = ""
            } label: {
                Label("Add Rule", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(isAdding)
        }
    }

    private func addConfig() {
        // Find target across all bridges
        var targetType: HotkeyBinding.TargetType?
        var targetName: String?
        for bridge in bridgeManager.bridges {
            if let room = bridge.client.rooms.first(where: { $0.id == selectedTargetId }) {
                targetType = .room; targetName = room.name; break
            }
            if let zone = bridge.client.zones.first(where: { $0.id == selectedTargetId }) {
                targetType = .zone; targetName = zone.name; break
            }
        }
        guard let type = targetType, let name = targetName else { return }

        let wakeSceneName: String? = selectedSceneId.isEmpty
            ? nil
            : scenesForSelected.first(where: { $0.id == selectedSceneId })?.name

        let config = SleepWakeConfig(
            targetType: type,
            targetId: selectedTargetId,
            targetName: name,
            mode: selectedMode,
            wakeSceneId: selectedSceneId.isEmpty ? nil : selectedSceneId,
            wakeSceneName: wakeSceneName
        )
        sleepWakeManager.add(config: config)
        resetAddFlow()
    }

    private func resetAddFlow() {
        isAdding = false
        selectedTargetId = ""
        selectedMode = .both
        selectedSceneId = ""
    }
}

extension SleepWakeMode {
    var displayName: String {
        switch self {
        case .sleepOnly: "Sleep"
        case .wakeOnly: "Wake"
        case .both: "Both"
        }
    }
}
