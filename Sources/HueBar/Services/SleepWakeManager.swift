import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class SleepWakeManager {
    private static let storageKey = "huebar.sleepWakeConfigs"

    var configs: [SleepWakeConfig] = []

    private var apiClient: HueAPIClient?
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

    func configure(apiClient: HueAPIClient) {
        self.apiClient = apiClient
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
        guard let apiClient else { return }
        let sleepConfigs = configs.filter { $0.mode == .sleepOnly || $0.mode == .both }
        await withTaskGroup(of: Void.self) { group in
            for config in sleepConfigs {
                guard let glId = groupedLightId(for: config, apiClient: apiClient),
                      apiClient.groupedLight(for: glId)?.isOn == true else { continue }
                group.addTask { try? await apiClient.toggleGroupedLight(id: glId, on: false) }
            }
        }
    }

    private func handleWake() async {
        try? await Task.sleep(for: .seconds(2))

        guard let apiClient else { return }

        for config in configs where config.mode == .wakeOnly || config.mode == .both {
            guard let groupedLightId = groupedLightId(for: config, apiClient: apiClient) else { continue }
            if let sceneId = config.wakeSceneId {
                try? await apiClient.recallScene(id: sceneId)
            } else {
                try? await apiClient.toggleGroupedLight(id: groupedLightId, on: true)
            }
        }
    }

    // MARK: - Helpers

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
