import SwiftUI

@main
struct HueBarApp: App {
    @State private var discovery = HueBridgeDiscovery()
    @State private var authService = HueAuthService()
    @State private var apiClient: HueAPIClient?

    private static let bridgeIPKey = "huebar.bridgeIP"

    var body: some Scene {
        MenuBarExtra("HueBar", systemImage: menuBarIcon) {
            mainView
                .frame(width: 300)
                .onAppear { restoreSession() }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated, apiClient == nil,
                       let key = authService.applicationKey,
                       let ip = authService.bridgeIP {
                        UserDefaults.standard.set(ip, forKey: Self.bridgeIPKey)
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

    private func restoreSession() {
        guard apiClient == nil,
              let key = KeychainService.load(),
              let ip = UserDefaults.standard.string(forKey: Self.bridgeIPKey)
        else { return }
        apiClient = HueAPIClient(bridgeIP: ip, applicationKey: key)
    }

    private func signOut() {
        authService.signOut()
        apiClient = nil
        UserDefaults.standard.removeObject(forKey: Self.bridgeIPKey)
    }
}
