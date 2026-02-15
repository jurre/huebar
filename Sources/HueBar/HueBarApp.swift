import SwiftUI

@main
struct HueBarApp: App {
    @State private var discovery = HueBridgeDiscovery()
    @State private var authService = HueAuthService()
    @State private var bridgeManager = BridgeManager()
    @State private var hotkeyManager = HotkeyManager()
    @State private var sleepWakeManager = SleepWakeManager()

    init() {
        // Load stored bridges (new format or migrated from legacy)
        let credentials = CredentialStore.loadBridges()
        for cred in credentials {
            _bridgeManager.wrappedValue.addBridge(credentials: cred)
        }
        // Connect immediately so the menu bar icon reflects light state
        if !credentials.isEmpty {
            let manager = _bridgeManager.wrappedValue
            Task { await manager.connectAll() }
        }
    }

    var body: some Scene {
        MenuBarExtra("HueBar", systemImage: menuBarIcon) {
            mainView
                .frame(width: 300)
        }
        .menuBarExtraStyle(.window)
    }

    private var isSetupComplete: Bool {
        !bridgeManager.bridges.isEmpty
    }

    private var menuBarIcon: String {
        guard isSetupComplete else { return "lightbulb" }
        return bridgeManager.bridges.contains { bridge in
            bridge.client.groupedLights.contains(where: \.isOn)
        } ? "lightbulb.fill" : "lightbulb"
    }

    @ViewBuilder
    private var mainView: some View {
        if isSetupComplete {
            MenuBarView(
                bridgeManager: bridgeManager,
                hotkeyManager: hotkeyManager,
                sleepWakeManager: sleepWakeManager,
                onSignOut: signOut
            )
        } else {
            SetupView(
                discovery: discovery,
                authService: authService,
                bridgeManager: bridgeManager,
                onSetupComplete: completeSetup
            )
        }
    }

    private func completeSetup() {
        authService.authState = .authenticated(applicationKey: "stored")
        configureHotkeyHandler()
        configureSleepWake()
        Task { await bridgeManager.connectAll() }
    }

    private func signOut() {
        bridgeManager.removeAll()
        CredentialStore.delete()
        authService.signOut()
        sleepWakeManager.stopObserving()
        hotkeyManager.onHotkeyTriggered = nil
    }

    private func configureHotkeyHandler() {
        hotkeyManager.onHotkeyTriggered = { binding in
            for bridge in bridgeManager.bridges {
                let client = bridge.client
                let groupedLightId: String? = switch binding.targetType {
                case .room: client.rooms.first(where: { $0.id == binding.targetId })?.groupedLightId
                case .zone: client.zones.first(where: { $0.id == binding.targetId })?.groupedLightId
                }
                guard let groupedLightId,
                      let groupedLight = client.groupedLight(for: groupedLightId) else { continue }
                Task {
                    try? await client.toggleGroupedLight(id: groupedLightId, on: !groupedLight.isOn)
                }
                return
            }
        }
    }

    private func configureSleepWake() {
        // For now, configure with the first bridge's client
        if let primary = bridgeManager.bridges.first {
            sleepWakeManager.configure(apiClient: primary.client)
        }
    }
}
