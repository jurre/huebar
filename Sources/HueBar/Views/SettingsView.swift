import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var apiClient: HueAPIClient
    @Bindable var hotkeyManager: HotkeyManager
    @Bindable var sleepWakeManager: SleepWakeManager
    var onSignOut: () -> Void
    var onBack: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
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

                    // Shortcuts section
                    SectionHeaderView(title: "SHORTCUTS")

                    ShortcutsSettingsView(hotkeyManager: hotkeyManager, apiClient: apiClient)
                        .padding(.horizontal)

                    // Sleep / Wake section
                    SectionHeaderView(title: "SLEEP / WAKE")

                    SleepWakeSettingsView(sleepWakeManager: sleepWakeManager, apiClient: apiClient)
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

}
