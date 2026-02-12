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
            Task { await apiClient.fetchAll(); apiClient.startEventStream() }
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
                            LightRowView(apiClient: apiClient, name: room.name, archetype: room.metadata.archetype, groupedLightId: room.groupedLightId, groupId: room.id, isPinned: apiClient.isRoomPinned(room.id)) {
                                withAnimation(.easeInOut(duration: 0.25)) { selectedRoom = room }
                            }
                            .contextMenu {
                                Button(apiClient.isRoomPinned(room.id) ? "Unpin" : "Pin to Top") {
                                    withAnimation { apiClient.toggleRoomPin(room.id) }
                                }
                            }
                        }

                        // Zones
                        if !apiClient.zones.isEmpty {
                            sectionHeader("Zones", icon: "square.grid.2x2")

                            ForEach(apiClient.zones) { zone in
                                LightRowView(apiClient: apiClient, name: zone.name, archetype: zone.metadata.archetype, groupedLightId: zone.groupedLightId, groupId: zone.id, isPinned: apiClient.isZonePinned(zone.id)) {
                                    withAnimation(.easeInOut(duration: 0.25)) { selectedZone = zone }
                                }
                                .contextMenu {
                                    Button(apiClient.isZonePinned(zone.id) ? "Unpin" : "Pin to Top") {
                                        withAnimation { apiClient.toggleZonePin(zone.id) }
                                    }
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
