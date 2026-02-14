import SwiftUI

@main
struct HueBarApp: App {
    @State private var discovery = HueBridgeDiscovery()
    @State private var authService = HueAuthService()
    @State private var apiClient: HueAPIClient?
    @State private var hotkeyManager = HotkeyManager()

    init() {
        if let creds = CredentialStore.load() {
            let client = try? HueAPIClient(
                bridgeIP: creds.bridgeIP,
                applicationKey: creds.applicationKey
            )
            _apiClient = State(initialValue: client)
            if let client {
                Self.configureHotkeyHandler(_hotkeyManager.wrappedValue, client: client)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("HueBar", systemImage: menuBarIcon) {
            mainView
                .frame(width: 300)
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated, apiClient == nil,
                       let key = authService.applicationKey,
                       let ip = authService.bridgeIP {
                        apiClient = try? HueAPIClient(bridgeIP: ip, applicationKey: key)
                    }
                    Self.configureHotkeyHandler(hotkeyManager, client: apiClient)
                }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        authService.isAuthenticated && apiClient != nil ? "lightbulb.fill" : "lightbulb"
    }

    @ViewBuilder
    private var mainView: some View {
        if authService.isAuthenticated, let client = apiClient {
            MenuBarView(apiClient: client, hotkeyManager: hotkeyManager, onSignOut: signOut)
        } else {
            SetupView(discovery: discovery, authService: authService)
        }
    }

    private func signOut() {
        apiClient?.stopEventStream()
        authService.signOut()
        apiClient = nil
        Self.configureHotkeyHandler(hotkeyManager, client: nil)
    }

    private static func configureHotkeyHandler(_ manager: HotkeyManager, client: HueAPIClient?) {
        manager.onHotkeyTriggered = { binding in
            guard let client else { return }
            let groupedLightId: String? = switch binding.targetType {
            case .room: client.rooms.first(where: { $0.id == binding.targetId })?.groupedLightId
            case .zone: client.zones.first(where: { $0.id == binding.targetId })?.groupedLightId
            }
            guard let groupedLightId,
                  let groupedLight = client.groupedLight(for: groupedLightId) else { return }
            Task {
                try? await client.toggleGroupedLight(id: groupedLightId, on: !groupedLight.isOn)
            }
        }
    }
}
