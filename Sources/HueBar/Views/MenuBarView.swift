import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @Bindable var apiClient: HueAPIClient
    var onSignOut: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
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
                            lightRow(name: room.name, groupedLightId: room.groupedLightId)
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
                                lightRow(name: zone.name, groupedLightId: zone.groupedLightId)
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
        .frame(width: 300)
        .onAppear {
            Task { await apiClient.fetchAll() }
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

    private func lightRow(name: String, groupedLightId: String?) -> some View {
        HStack {
            Text(name)
            Spacer()
            Toggle("", isOn: toggleBinding(for: groupedLightId))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(groupedLightId == nil)
        }
        .padding(.horizontal)
    }

    // MARK: - Toggle Binding

    private func toggleBinding(for groupedLightId: String?) -> Binding<Bool> {
        Binding(
            get: { apiClient.groupedLight(for: groupedLightId)?.isOn ?? false },
            set: { newValue in
                guard let id = groupedLightId else { return }
                Task { try? await apiClient.toggleGroupedLight(id: id, on: newValue) }
            }
        )
    }
}
