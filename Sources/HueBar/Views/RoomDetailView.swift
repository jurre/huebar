import SwiftUI

struct RoomDetailView: View {
    @Bindable var apiClient: HueAPIClient
    let name: String
    let groupedLightId: String?
    let groupId: String
    var room: Room? = nil
    var zone: Zone? = nil
    let onBack: () -> Void

    @State private var sliderBrightness: Double = 0
    @State private var debounceTask: Task<Void, Never>?

    private var groupedLight: GroupedLight? {
        apiClient.groupedLight(for: groupedLightId)
    }

    private var isOn: Bool {
        groupedLight?.isOn ?? false
    }

    private var roomLights: [HueLight] {
        if let room { return apiClient.lights(forRoom: room) }
        if let zone { return apiClient.lights(forZone: zone) }
        return []
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
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)

                Text(name)
                    .font(.headline)

                Spacer()

                Toggle("", isOn: toggleBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(groupedLightId == nil)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            // Brightness slider
            if isOn, groupedLightId != nil {
                HStack(spacing: 6) {
                    Image(systemName: "sun.min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $sliderBrightness, in: 1...100)
                        .controlSize(.small)
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // Scrollable content: scenes + lights
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Scenes grid
                    let groupScenes = apiClient.scenes(for: groupId)
                    if !groupScenes.isEmpty {
                        Text("MY SCENES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: sceneColumns, spacing: 8) {
                            ForEach(groupScenes) { scene in
                                SceneCard(
                                    scene: scene,
                                    isActive: apiClient.activeSceneId == scene.id
                                ) {
                                    Task { try? await apiClient.recallScene(id: scene.id) }
                                }
                            }
                        }
                    }

                    // Lights grid
                    let lightsInRoom = roomLights
                    if !lightsInRoom.isEmpty {
                        Text("LIGHTS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: lightColumns, spacing: 8) {
                            ForEach(lightsInRoom) { light in
                                LightCard(apiClient: apiClient, light: light)
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
        }
        .onChange(of: groupedLight?.brightness) { _, newValue in
            if let newValue {
                sliderBrightness = max(newValue, 1)
            }
        }
        .onChange(of: sliderBrightness) { _, newValue in
            guard let id = groupedLightId else { return }
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                try? await apiClient.setBrightness(groupedLightId: id, brightness: newValue)
            }
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
