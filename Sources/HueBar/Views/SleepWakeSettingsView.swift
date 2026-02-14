import SwiftUI

struct SleepWakeSettingsView: View {
    @Bindable var sleepWakeManager: SleepWakeManager
    @Bindable var apiClient: HueAPIClient

    @State private var isAdding = false
    @State private var selectedTargetId: String = ""
    @State private var selectedMode: SleepWakeMode = .both
    @State private var selectedSceneId: String = ""

    private var availableTargets: [(id: String, name: String, type: HotkeyBinding.TargetType)] {
        let existing = Set(sleepWakeManager.configs.map(\.targetId))
        let rooms = apiClient.rooms
            .filter { !existing.contains($0.id) }
            .map { (id: $0.id, name: $0.name, type: HotkeyBinding.TargetType.room) }
        let zones = apiClient.zones
            .filter { !existing.contains($0.id) }
            .map { (id: $0.id, name: $0.name, type: HotkeyBinding.TargetType.zone) }
        return rooms + zones
    }

    private var scenesForSelected: [HueScene] {
        guard !selectedTargetId.isEmpty else { return [] }
        return apiClient.scenes(for: selectedTargetId)
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
                        ForEach(availableTargets, id: \.id) { target in
                            Text(target.name).tag(target.id)
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
        guard let target = availableTargets.first(where: { $0.id == selectedTargetId }) else { return }

        let wakeSceneName: String? = selectedSceneId.isEmpty
            ? nil
            : scenesForSelected.first(where: { $0.id == selectedSceneId })?.name

        let config = SleepWakeConfig(
            targetType: target.type,
            targetId: target.id,
            targetName: target.name,
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
