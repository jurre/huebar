import SwiftUI

@main
struct HueBarApp: App {
    @State private var discovery = HueBridgeDiscovery()
    @State private var authService = HueAuthService()
    @State private var apiClient: HueAPIClient?

    init() {
        if let creds = CredentialStore.load() {
            _apiClient = State(initialValue: HueAPIClient(
                bridgeIP: creds.bridgeIP,
                applicationKey: creds.applicationKey
            ))
        } else if let legacyIP = UserDefaults.standard.string(forKey: "huebar.bridgeIP") {
            // Migrate known bridge IP from legacy UserDefaults so SetupView can offer it
            _discovery = State(initialValue: {
                let d = HueBridgeDiscovery()
                d.manualIP = legacyIP
                return d
            }())
            UserDefaults.standard.removeObject(forKey: "huebar.bridgeIP")
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
                        apiClient = HueAPIClient(bridgeIP: ip, applicationKey: key)
                    }
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
            MenuBarView(apiClient: client, onSignOut: signOut)
        } else {
            SetupView(discovery: discovery, authService: authService)
        }
    }

    private func signOut() {
        authService.signOut()
        apiClient = nil
    }
}
