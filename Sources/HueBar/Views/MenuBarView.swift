import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @Bindable var apiClient: HueAPIClient
    var onSignOut: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selectedRoom: Room?
    @State private var selectedZone: Zone?

    var body: some View {
        VStack(spacing: 0) {
            if let room = selectedRoom {
                RoomDetailView(
                    apiClient: apiClient,
                    name: room.name,
                    groupedLightId: room.groupedLightId,
                    groupId: room.id,
                    room: room,
                    onBack: { withAnimation(.easeInOut(duration: 0.25)) { selectedRoom = nil } }
                )
                .transition(.move(edge: .trailing))
            } else if let zone = selectedZone {
                RoomDetailView(
                    apiClient: apiClient,
                    name: zone.name,
                    groupedLightId: zone.groupedLightId,
                    groupId: zone.id,
                    zone: zone,
                    onBack: { withAnimation(.easeInOut(duration: 0.25)) { selectedZone = nil } }
                )
                .transition(.move(edge: .trailing))
            } else {
                roomListView
                    .transition(.move(edge: .leading))
            }
        }
        .frame(width: 300, height: 450)
        .clipped()
        .preferredColorScheme(.dark)
        .onAppear {
            Task { await apiClient.fetchAll() }
        }
    }

    // MARK: - Room List

    private var roomListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("HueBar")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await apiClient.fetchAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(apiClient.isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Content
            if apiClient.isLoading && apiClient.rooms.isEmpty && apiClient.zones.isEmpty {
                Spacer()
                ProgressView("Loading…")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let error = apiClient.lastError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }

                        // Rooms
                        sectionHeader("Rooms", icon: "house")

                        ForEach(apiClient.rooms) { room in
                            LightRowView(apiClient: apiClient, name: room.name, archetype: room.metadata.archetype, groupedLightId: room.groupedLightId, groupId: room.id) {
                                withAnimation(.easeInOut(duration: 0.25)) { selectedRoom = room }
                            }
                            .draggable(room.id)
                            .dropDestination(for: String.self) { droppedIds, _ in
                                guard let fromId = droppedIds.first else { return false }
                                guard apiClient.rooms.contains(where: { $0.id == fromId }) else { return false }
                                apiClient.moveRoom(fromId: fromId, toId: room.id)
                                return true
                            }
                        }

                        // Zones
                        if !apiClient.zones.isEmpty {
                            sectionHeader("Zones", icon: "square.grid.2x2")

                            ForEach(apiClient.zones) { zone in
                                LightRowView(apiClient: apiClient, name: zone.name, archetype: zone.metadata.archetype, groupedLightId: zone.groupedLightId, groupId: zone.id) {
                                    withAnimation(.easeInOut(duration: 0.25)) { selectedZone = zone }
                                }
                                .draggable(zone.id)
                                .dropDestination(for: String.self) { droppedIds, _ in
                                    guard let fromId = droppedIds.first else { return false }
                                    guard apiClient.zones.contains(where: { $0.id == fromId }) else { return false }
                                    apiClient.moveZone(fromId: fromId, toId: zone.id)
                                    return true
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Footer
            VStack(spacing: 4) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                    .padding(.horizontal)

                Divider()

                Button("Sign Out", action: onSignOut)
                    .buttonStyle(.borderless)
                Button("Quit HueBar") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 4)
    }
}

// MARK: - LightRowView (main list row with brightness slider)

private struct LightRowView: View {
    @Bindable var apiClient: HueAPIClient
    let name: String
    let archetype: String?
    let groupedLightId: String?
    let groupId: String
    let onTap: () -> Void

    @State private var sliderBrightness: Double = 0
    @State private var debounceTask: Task<Void, Never>?

    private var groupedLight: GroupedLight? {
        apiClient.groupedLight(for: groupedLightId)
    }

    private var isOn: Bool {
        groupedLight?.isOn ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Icon + Name + Toggle row
            HStack(spacing: 8) {
                Image(systemName: ArchetypeIcon.systemName(for: archetype))
                    .font(.title2)
                    .foregroundStyle(isOn ? .white : .secondary)
                    .frame(width: 28)

                HStack {
                    Text(name)
                        .fontWeight(.medium)
                        .foregroundStyle(isOn ? .white : .primary)
                        .shadow(color: isOn ? .black.opacity(0.3) : .clear, radius: 2, y: 1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.6)) : AnyShapeStyle(.tertiary))
                }

                Toggle("", isOn: toggleBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(groupedLightId == nil)
            }

            // Brightness slider (always visible for consistent card height)
            HStack(spacing: 4) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundStyle(isOn ? .white.opacity(0.6) : .white.opacity(0.2))
                Slider(value: $sliderBrightness, in: 1...100)
                    .controlSize(.small)
                    .tint(isOn ? .white.opacity(0.8) : .white.opacity(0.15))
                    .disabled(!isOn)
                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                    .foregroundStyle(isOn ? .white.opacity(0.6) : .white.opacity(0.2))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardGradient)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .padding(.horizontal)
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

    private var cardGradient: some ShapeStyle {
        guard isOn else {
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
        let colors = apiClient.activeSceneColors(for: groupId)
        if colors.count >= 2 {
            return AnyShapeStyle(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        } else if let first = colors.first {
            return AnyShapeStyle(
                LinearGradient(colors: [first, first.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        } else {
            return AnyShapeStyle(Color.white.opacity(0.15))
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

// MARK: - RoomDetailView (scene selection grid)

private struct RoomDetailView: View {
    @Bindable var apiClient: HueAPIClient
    let name: String
    let groupedLightId: String?
    let groupId: String
    let onBack: () -> Void

    @State private var sliderBrightness: Double = 0
    @State private var debounceTask: Task<Void, Never>?

    private var groupedLight: GroupedLight? {
        apiClient.groupedLight(for: groupedLightId)
    }

    private var isOn: Bool {
        groupedLight?.isOn ?? false
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
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

            // Scenes grid
            let groupScenes = apiClient.scenes(for: groupId)
            if groupScenes.isEmpty {
                Spacer()
                Text("No scenes")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MY SCENES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 8) {
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
                    .padding()
                }
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

// MARK: - SceneCard

private struct SceneCard: View {
    let scene: HueScene
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Spacer()
                Text(scene.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(sceneGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var sceneGradient: some ShapeStyle {
        let colors = scene.paletteColors
        if colors.count >= 2 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else if let first = colors.first {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [first, first.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            // Fallback warm gradient for scenes without palette data
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.orange.opacity(0.6), .purple.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}
