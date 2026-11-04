import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.huebar", category: "SleepWakeManager")

@Observable
@MainActor
final class SleepWakeManager {
    private static let storageKey = "huebar.sleepWakeConfigs"

    var configs: [SleepWakeConfig] = []

    private var bridgeManager: BridgeManager?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init() {
        configs = Self.loadConfigs()
    }

    // MARK: - Public API

    func add(config: SleepWakeConfig) {
        guard !configs.contains(where: { $0.targetId == config.targetId }) else { return }
        configs.append(config)
        saveConfigs()
    }

    func remove(id: String) {
        configs.removeAll(where: { $0.targetId == id })
        saveConfigs()
    }

    func configure(bridgeManager: BridgeManager) {
        self.bridgeManager = bridgeManager
        startObserving()
    }

    func stopObserving() {
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        sleepObserver = nil
        wakeObserver = nil
    }

    // MARK: - Notification Observers

    private func startObserving() {
        stopObserving()

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleSleep()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleWake()
            }
        }
    }

    // MARK: - Sleep / Wake Handlers

    private func handleSleep() async {
        let sleepConfigs = configs.filter { $0.mode == .sleepOnly || $0.mode == .both }
        await withTaskGroup(of: Void.self) { group in
            for config in sleepConfigs {
                guard let (apiClient, glId) = resolveTarget(for: config) else { continue }
                guard let groupedLight = apiClient.groupedLight(for: glId) else {
                    logger.error("Cannot run sleep rule for \(config.targetId): grouped light \(glId) is unavailable")
                    continue
                }
                guard groupedLight.isOn else { continue }
                group.addTask {
                    do {
                        try await apiClient.toggleGroupedLight(id: glId, on: false)
                    } catch {
                        logger.error("Failed to toggle light off \(glId): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func handleWake() async {
        try? await Task.sleep(for: .seconds(2))

        let wakeConfigs = configs.filter { $0.mode == .wakeOnly || $0.mode == .both }
        await withTaskGroup(of: Void.self) { group in
            for config in wakeConfigs {
                guard let (apiClient, glId) = resolveTarget(for: config) else { continue }
                if let sceneId = config.wakeSceneId {
                    group.addTask {
                        do {
                            try await apiClient.recallScene(id: sceneId)
                        } catch {
                            logger.error("Failed to recall scene \(sceneId): \(error.localizedDescription)")
                        }
                    }
                } else {
                    group.addTask {
                        do {
                            try await apiClient.toggleGroupedLight(id: glId, on: true)
                        } catch {
                            logger.error("Failed to toggle light on \(glId): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func resolveTarget(for config: SleepWakeConfig) -> (HueAPIClient, String)? {
        guard let bridgeManager else {
            logger.error("Cannot run sleep/wake rule for \(config.targetId): bridge manager is not configured")
            return nil
        }
        for bridge in bridgeManager.bridges {
            if let glId = groupedLightId(for: config, apiClient: bridge.client) {
                return (bridge.client, glId)
            }
        }
        logger.error("Cannot run sleep/wake rule for \(config.targetId): target or grouped light not found on any configured bridge")
        return nil
    }

    private func groupedLightId(for config: SleepWakeConfig, apiClient: HueAPIClient) -> String? {
        switch config.targetType {
        case .room:
            return apiClient.rooms.first(where: { $0.id == config.targetId })?.groupedLightId
        case .zone:
            return apiClient.zones.first(where: { $0.id == config.targetId })?.groupedLightId
        }
    }

    // MARK: - Persistence

    private func saveConfigs() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func loadConfigs() -> [SleepWakeConfig] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let configs = try? JSONDecoder().decode([SleepWakeConfig].self, from: data) else {
            return []
        }
        return configs
    }
}
