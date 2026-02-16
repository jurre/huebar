import SwiftUI

struct RoomDetailView: View {
    enum GroupTarget {
        case room(Room)
        case zone(Zone)
    }

    @Bindable var apiClient: HueAPIClient
    let target: GroupTarget
    let onBack: () -> Void

    @State private var sliderBrightness: Double = 0
    @State private var sliderMirek: Int = 350
    @State private var sliderSpeed: Double = 0.5
    @State private var isUserDraggingBrightness = false
    @State private var isUserDraggingSpeed = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var colorTempDebounceTask: Task<Void, Never>?
    @State private var speedDebounceTask: Task<Void, Never>?
    @State private var selectedLightId: String? = nil

    private var group: any LightGroup {
        switch target {
        case .room(let room): return room
        case .zone(let zone): return zone
        }
    }

    private var name: String { group.name }
    private var groupedLightId: String? { group.groupedLightId }
    private var groupId: String { group.id }

    private var groupedLight: GroupedLight? {
        apiClient.groupedLight(for: groupedLightId)
    }

    private var isOn: Bool {
        groupedLight?.isOn ?? false
    }

    private var roomLights: [HueLight] {
        switch target {
        case .room(let room): return apiClient.lights(forRoom: room)
        case .zone(let zone): return apiClient.lights(forZone: zone)
        }
    }

    private var selectedLight: HueLight? {
        guard let id = selectedLightId else { return nil }
        return roomLights.first(where: { $0.id == id })
    }

    private var activeSceneForGroup: HueScene? {
        apiClient.activeScene(for: groupId)
    }

    private var isActiveSceneDynamic: Bool {
        apiClient.isActiveSceneDynamic(for: groupId)
    }

    private let sceneColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private let lightColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and toggle
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text(name)
                            .font(.headline)
                    }
                }
                .buttonStyle(.borderless)

                Spacer()

                Toggle("", isOn: toggleBinding)
                    .toggleStyle(.switch)
                    .tint(.hueAccent)
                    .labelsHidden()
                    .disabled(groupedLightId == nil)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            // Sliders
            if isOn, groupedLightId != nil {
                VStack(spacing: 10) {
                    // Brightness slider
                    HStack(spacing: 6) {
                        Image(systemName: "sun.min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $sliderBrightness, in: 1...100) { editing in
                            isUserDraggingBrightness = editing
                        }
                            .controlSize(.small)
                            .tint(.hueAccent)
                            .accessibilityLabel("Brightness")
                            .accessibilityValue(String(format: "%.0f%%", sliderBrightness))
                        Image(systemName: "sun.max.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Color temperature slider
                    if groupedLight?.colorTemperature != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "flame")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            ColorTemperatureSlider(mirek: $sliderMirek) { newMirek in
                                guard let id = groupedLightId else { return }
                                debounce(task: &colorTempDebounceTask) {
                                    try? await apiClient.setGroupedLightColorTemperature(id: id, mirek: newMirek)
                                }
                            }
                            Image(systemName: "snowflake")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                        }
                    }

                    // Speed slider (visible when active scene is in dynamic mode)
                    if isActiveSceneDynamic {
                        HStack(spacing: 6) {
                            Image(systemName: "tortoise")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Slider(value: $sliderSpeed, in: 0...1) { editing in
                                isUserDraggingSpeed = editing
                            }
                                .controlSize(.small)
                                .tint(.hueAccent)
                                .accessibilityLabel("Scene speed")
                                .accessibilityValue(String(format: "%.0f%%", sliderSpeed * 100))
                            Image(systemName: "hare")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // Scrollable content: light detail or scenes + lights
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Light detail panel (replaces scenes when a light is selected)
                    if let selected = selectedLight {
                        LightDetailView(
                            apiClient: apiClient,
                            light: selected,
                            onDone: { selectedLightId = nil }
                        )
                    } else {
                        // Scenes grid
                        let groupScenes = apiClient.scenes(for: groupId)
                        if !groupScenes.isEmpty {
                            SectionHeaderView(title: "MY SCENES")

                            LazyVGrid(columns: sceneColumns, spacing: 8) {
                                ForEach(groupScenes) { scene in
                                    let sceneIsActive = activeSceneForGroup?.id == scene.id
                                    SceneCard(
                                        scene: scene,
                                        isActive: sceneIsActive,
                                        isDynamic: sceneIsActive && isActiveSceneDynamic,
                                        onTap: {
                                            Task { try? await apiClient.recallScene(id: scene.id) }
                                        },
                                        onPlayPause: {
                                            Task {
                                                // Toggle dynamic mode on the active scene
                                                try? await apiClient.recallScene(id: scene.id, dynamic: !isActiveSceneDynamic)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }

                    // Lights grid
                    let lightsInRoom = roomLights
                    if !lightsInRoom.isEmpty {
                        SectionHeaderView(title: "LIGHTS")

                        LazyVGrid(columns: lightColumns, spacing: 8) {
                            ForEach(lightsInRoom) { light in
                                LightCard(
                                    apiClient: apiClient,
                                    light: light,
                                    isSelected: selectedLightId == light.id,
                                    onTap: { selectedLightId = light.id }
                                )
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            sliderBrightness = max(groupedLight?.brightness ?? 0, 1)
            sliderMirek = groupedLight?.mirek ?? 350
            sliderSpeed = activeSceneForGroup?.speed ?? 0.5
        }
        .onChange(of: groupedLight?.brightness) { _, newValue in
            if let newValue, !isUserDraggingBrightness {
                sliderBrightness = max(newValue, 1)
            }
        }
        .onChange(of: groupedLight?.mirek) { _, newValue in
            if let newValue {
                sliderMirek = newValue
            }
        }
        .onChange(of: activeSceneForGroup?.speed) { _, newValue in
            if let newValue, !isUserDraggingSpeed {
                sliderSpeed = newValue
            }
        }
        .onChange(of: sliderBrightness) { _, newValue in
            guard isUserDraggingBrightness, let id = groupedLightId else { return }
            debounce(task: &debounceTask) {
                try? await apiClient.setBrightness(groupedLightId: id, brightness: newValue)
            }
        }
        .onChange(of: sliderSpeed) { _, newValue in
            guard isUserDraggingSpeed, let sceneId = activeSceneForGroup?.id else { return }
            debounce(task: &speedDebounceTask) {
                try? await apiClient.setSceneSpeed(id: sceneId, speed: newValue)
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            colorTempDebounceTask?.cancel()
            speedDebounceTask?.cancel()
        }
    }


    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                guard let id = groupedLightId else { return }
                Task { try? await apiClient.toggleGroupedLight(id: id, on: newValue) }
            }
        )
    }
}
