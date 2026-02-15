import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var bridgeManager: BridgeManager
    @Bindable var hotkeyManager: HotkeyManager
    @Bindable var sleepWakeManager: SleepWakeManager
    var onSignOut: () -> Void
    var onBack: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var editingBridgeId: String?
    @State private var editingBridgeName: String = ""
    @State private var showAddBridge = false

    var body: some View {
        if showAddBridge {
            AddBridgeView(bridgeManager: bridgeManager) {
                withAnimation(.easeInOut(duration: 0.25)) { showAddBridge = false }
            }
            .transition(.move(edge: .trailing))
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)

                Text("Settings")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // General section
                    SectionHeaderView(title: "GENERAL")

                    VStack(spacing: 12) {
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
                    }
                    .padding(.horizontal)

                    // Bridges section
                    SectionHeaderView(title: "BRIDGES")

                    VStack(spacing: 8) {
                        ForEach(bridgeManager.bridges) { bridge in
                            bridgeRow(bridge)
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showAddBridge = true }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Add Bridge")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // Shortcuts section
                    SectionHeaderView(title: "SHORTCUTS")

                    ShortcutsSettingsView(hotkeyManager: hotkeyManager, bridgeManager: bridgeManager)
                        .padding(.horizontal)

                    // Sleep / Wake section
                    SectionHeaderView(title: "SLEEP / WAKE")

                    SleepWakeSettingsView(sleepWakeManager: sleepWakeManager, bridgeManager: bridgeManager)
                        .padding(.horizontal)

                    Divider()
                        .padding(.top, 4)

                    // Footer actions
                    VStack(spacing: 10) {
                        Button("Sign Out", action: onSignOut)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        Button("Quit HueBar") {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                }
                .padding()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func bridgeRow(_ bridge: BridgeConnection) -> some View {
        HStack {
            if editingBridgeId == bridge.id {
                TextField("Name", text: $editingBridgeName, onCommit: {
                    bridge.name = editingBridgeName
                    let creds = BridgeCredentials(
                        id: bridge.id,
                        bridgeIP: bridge.client.bridgeIP,
                        applicationKey: bridge.client.applicationKey,
                        name: editingBridgeName
                    )
                    try? CredentialStore.saveBridge(creds)
                    editingBridgeId = nil
                })
                .textFieldStyle(.roundedBorder)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bridge.name)
                        .fontWeight(.medium)
                    Text(bridge.client.bridgeIP)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusIndicator(bridge.status)

                Menu {
                    Button("Rename") {
                        editingBridgeName = bridge.name
                        editingBridgeId = bridge.id
                    }
                    if bridgeManager.bridges.count > 1 {
                        Button("Remove", role: .destructive) {
                            bridgeManager.removeBridge(id: bridge.id)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private func statusIndicator(_ status: BridgeConnectionStatus) -> some View {
        Group {
            switch status {
            case .connected:
                Circle().fill(.green).frame(width: 8, height: 8)
            case .connecting:
                ProgressView().controlSize(.mini)
            case .error:
                Circle().fill(.red).frame(width: 8, height: 8)
            }
        }
    }
}
