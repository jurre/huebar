import SwiftUI

struct MenuBarView: View {
    @Bindable var apiClient: HueAPIClient
    var onSignOut: () -> Void

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
                        }

                        // Zones
                        if !apiClient.zones.isEmpty {
                            sectionHeader("Zones", icon: "square.grid.2x2")

                            ForEach(apiClient.zones) { zone in
                                lightRow(name: zone.name, groupedLightId: zone.groupedLightId)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Footer
            VStack(spacing: 4) {
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
