import Foundation
import os

private let logger = Logger(subsystem: "com.huebar", category: "AppCoordinator")

@Observable
@MainActor
final class AppCoordinator {
    let discovery: HueBridgeDiscovery
    let authService: HueAuthService
    let bridgeManager: BridgeManager
    let hotkeyManager: HotkeyManager
    let sleepWakeManager: SleepWakeManager

    init() {
        let discovery = HueBridgeDiscovery()
        let authService = HueAuthService()
        let bridgeManager = BridgeManager()
        let hotkeyManager = HotkeyManager()
        let sleepWakeManager = SleepWakeManager()

        self.discovery = discovery
        self.authService = authService
        self.bridgeManager = bridgeManager
        self.hotkeyManager = hotkeyManager
        self.sleepWakeManager = sleepWakeManager

        let credentials = CredentialStore.loadBridges()
        for cred in credentials {
            bridgeManager.addBridge(credentials: cred)
        }
        if !credentials.isEmpty {
            configureHotkeyHandler(hotkeyManager: hotkeyManager, bridgeManager: bridgeManager)
            configureSleepWake(sleepWakeManager: sleepWakeManager, bridgeManager: bridgeManager)
            Task { await bridgeManager.connectAll() }
        }
    }

    func completeSetup() {
        authService.authState = .authenticated(applicationKey: "stored")
        configureHotkeyHandler(hotkeyManager: hotkeyManager, bridgeManager: bridgeManager)
        configureSleepWake(sleepWakeManager: sleepWakeManager, bridgeManager: bridgeManager)
        Task { await bridgeManager.connectAll() }
    }

    func signOut() {
        bridgeManager.removeAll()
        CredentialStore.delete()
        authService.signOut()
        sleepWakeManager.stopObserving()
        hotkeyManager.onHotkeyTriggered = nil
    }

    private func configureHotkeyHandler(hotkeyManager: HotkeyManager, bridgeManager: BridgeManager) {
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
                    do {
                        try await client.toggleGroupedLight(id: groupedLightId, on: !groupedLight.isOn)
                    } catch {
                        logger.error("Failed to toggle light \(groupedLightId): \(error.localizedDescription)")
                    }
                }
                return
            }
        }
    }

    private func configureSleepWake(sleepWakeManager: SleepWakeManager, bridgeManager: BridgeManager) {
        if let primary = bridgeManager.bridges.first {
            sleepWakeManager.configure(apiClient: primary.client)
        }
    }
}
