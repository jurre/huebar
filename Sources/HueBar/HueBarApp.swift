import os
import SwiftUI

private let logger = Logger(subsystem: "com.huebar", category: "HueBarApp")

@main
struct HueBarApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("HueBar", systemImage: menuBarIcon) {
            mainView
                .frame(width: 300)
        }
        .menuBarExtraStyle(.window)
    }

    private var isSetupComplete: Bool {
        !coordinator.bridgeManager.bridges.isEmpty
    }

    private var menuBarIcon: String {
        guard isSetupComplete else { return "lightbulb" }
        return coordinator.bridgeManager.bridges.contains { bridge in
            bridge.client.groupedLights.contains(where: \.isOn)
        } ? "lightbulb.fill" : "lightbulb"
    }

    @ViewBuilder
    private var mainView: some View {
        if isSetupComplete {
            MenuBarView(
                bridgeManager: coordinator.bridgeManager,
                hotkeyManager: coordinator.hotkeyManager,
                sleepWakeManager: coordinator.sleepWakeManager,
                onSignOut: coordinator.signOut
            )
        } else {
            SetupView(
                discovery: coordinator.discovery,
                authService: coordinator.authService,
                bridgeManager: coordinator.bridgeManager,
                onSetupComplete: coordinator.completeSetup
            )
        }
    }
}

