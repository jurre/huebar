import Foundation
import Observation
import os

enum HueAPIError: Error, LocalizedError {
    case bridgeError(String)
    case invalidResponse
    case invalidResourceId
    case invalidBridgeIP

    var errorDescription: String? {
        switch self {
        case .bridgeError(let message): message
        case .invalidResponse: "Invalid response from bridge"
        case .invalidResourceId: "Invalid resource identifier"
        case .invalidBridgeIP: "Invalid bridge IP address"
        }
    }
}

@Observable
@MainActor
final class HueAPIClient {
    private static let logger = Logger(subsystem: "com.huebar", category: "HueAPIClient")
    @ObservationIgnored var failureLogHandler: ((String) -> Void)?

    private func logFailure(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
        failureLogHandler?(message)
    }

    private enum ControlOperation: String {
        case toggle, brightness, color, colorTemperature, recall, speed
    }

    private struct GroupColorPreview {
        let token: UUID
        var original: LightColor?
    }
    private var groupColorPreviews: [String: GroupColorPreview] = [:]
    /// Warm-white fallback for on, dimmable lights that do not report color temperature.
    private static let defaultWarmWhiteMirek = 370

    var rooms: [Room] = []
    var zones: [Zone] = []
    var groupedLights: [GroupedLight] = []
    var scenes: [HueScene] = []
    var lights: [HueLight] = []
    var activeSceneId: String?
    var activeSceneIsDynamic: Bool = false
    var isLoading: Bool = false
    var lastError: String?

    let orderManager = RoomOrderManager()

    let bridgeIP: String
    let applicationKey: String
    private let session: URLSession

    /// Parsed host (without port), cached from bridgeIP
    private let parsedHost: String
    /// Parsed port (if specified), cached from bridgeIP
    private let parsedPort: Int?

    /// Whether this client connects to a local mock bridge (uses HTTP instead of HTTPS)
    private var isLocalMock: Bool {
        parsedHost == "127.0.0.1" || parsedHost == "localhost"
    }

    /// The scheme to use for API requests
    private var scheme: String { isLocalMock ? "http" : "https" }

    /// The host component (without port)
    private var host: String { parsedHost }

    /// The port component (if specified)
    private var port: Int? { parsedPort }

    init(bridgeIP: String, applicationKey: String) throws {
        let parsed = IPValidation.parseHostPort(bridgeIP)
        let isLocal = parsed.host == "127.0.0.1" || parsed.host == "localhost"
        guard IPValidation.isValid(parsed.host) || isLocal else {
            throw HueAPIError.invalidBridgeIP
        }
        self.bridgeIP = bridgeIP
        self.applicationKey = applicationKey
        self.parsedHost = parsed.host
        self.parsedPort = parsed.port
        let config = URLSessionConfiguration.default
        if isLocal {
            // No TLS delegate needed for local mock bridges
            self.session = URLSession(configuration: config)
        } else {
            self.session = URLSession(
                configuration: config,
                delegate: HueBridgeTrustDelegate(bridgeIP: parsed.host),
                delegateQueue: nil
            )
        }
    }

    // Internal init for testing with a custom URLSession
    init(bridgeIP: String, applicationKey: String, session: URLSession) {
        let parsed = IPValidation.parseHostPort(bridgeIP)
        self.bridgeIP = bridgeIP
        self.applicationKey = applicationKey
        self.parsedHost = parsed.host
        self.parsedPort = parsed.port
        self.session = session
    }

    /// Fetch all rooms, zones, and grouped lights concurrently
    func fetchAll() async {
        isLoading = true
        lastError = nil

        do {
            async let fetchedRooms: [Room] = fetchRooms()
            async let fetchedZones: [Zone] = fetchZones()
            async let fetchedGroupedLights: [GroupedLight] = fetchGroupedLights()
            async let fetchedScenes: [HueScene] = fetchScenes()
            async let fetchedLights: [HueLight] = fetchLights()

            let (r, z, g, s, l) = try await (fetchedRooms, fetchedZones, fetchedGroupedLights, fetchedScenes, fetchedLights)
            rooms = r
            zones = z
            orderManager.sortRooms(&rooms)
            orderManager.sortZones(&zones)
            groupedLights = g
            scenes = s
            lights = l
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    /// Fetch rooms from the bridge
    func fetchRooms() async throws -> [Room] {
        try await fetch(path: "room")
    }

    /// Fetch zones from the bridge
    func fetchZones() async throws -> [Zone] {
        try await fetch(path: "zone")
    }

    /// Fetch all grouped lights
    func fetchGroupedLights() async throws -> [GroupedLight] {
        try await fetch(path: "grouped_light")
    }

    /// Fetch all scenes
    func fetchScenes() async throws -> [HueScene] {
        try await fetch(path: "scene")
    }

    /// Fetch all individual lights
    func fetchLights() async throws -> [HueLight] {
        try await fetch(path: "light")
    }

    /// Toggle an individual light on/off
    func toggleLight(id: String, on: Bool) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        applyLightOnOptimistically(id: id, on: on)

        do {
            try await sendControlRequest(
                path: "light/\(id)",
                operation: .toggle,
                body: try JSONEncoder().encode(["on": OnState(on: on)])
            )
        } catch {
            clearOptimisticLightToggle(id: id)
            await reconcileControlFailure { lights = try await fetchLights() }
            throw error
        }
    }

    func previewLightBrightness(id: String, brightness: Double) {
        guard Self.isValidResourceId(id) else { return }
        applyLightBrightnessOptimistically(id: id, brightness: brightness)
    }

    /// Set brightness for an individual light (0.0–100.0)
    func setLightBrightness(id: String, brightness: Double) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        let clamped = applyLightBrightnessOptimistically(id: id, brightness: brightness)

        do {
            try await sendControlRequest(
                path: "light/\(id)",
                operation: .brightness,
                body: try JSONEncoder().encode(["dimming": DimmingState(brightness: clamped)])
            )
        } catch {
            optimisticUpdates.clear(.brightness, for: .light, id: id)
            await reconcileControlFailure { lights = try await fetchLights() }
            throw error
        }
    }

    func previewLightColor(id: String, xy: CIEXYColor) {
        guard Self.isValidResourceId(id) else { return }
        applyLightColorOptimistically(id: id, xy: xy)
    }

    /// Set color for an individual light using CIE xy coordinates
    func setLightColor(id: String, xy: CIEXYColor) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        applyLightColorOptimistically(id: id, xy: xy)

        do {
            let body = try JSONEncoder().encode(["color": ["xy": ["x": xy.x, "y": xy.y]]])
            try await sendControlRequest(path: "light/\(id)", operation: .color, body: body)
        } catch {
            optimisticUpdates.clear(.color, for: .light, id: id)
            await reconcileControlFailure { lights = try await fetchLights() }
            throw error
        }
    }

    func previewLightColorTemperature(id: String, mirek: Int) {
        guard Self.isValidResourceId(id) else { return }
        applyLightColorTemperatureOptimistically(id: id, mirek: mirek)
    }

    /// Set color temperature for an individual light (mirek value: 153–500)
    func setLightColorTemperature(id: String, mirek: Int) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        let clampedMirek = applyLightColorTemperatureOptimistically(id: id, mirek: mirek)

        do {
            let body = try JSONEncoder().encode(["color_temperature": ["mirek": clampedMirek]])
            try await sendControlRequest(path: "light/\(id)", operation: .colorTemperature, body: body)
        } catch {
            optimisticUpdates.clear(.colorTemperature, for: .light, id: id)
            await reconcileControlFailure { lights = try await fetchLights() }
            throw error
        }
    }

    /// Get lights belonging to a room (room children are devices, lights have device owners)
    func lights(forRoom room: Room) -> [HueLight] {
        let deviceIds = Set(room.children.filter { $0.rtype == "device" }.map(\.rid))
        return lights.filter { deviceIds.contains($0.owner.rid) }
    }

    /// Get lights belonging to a zone (zone children reference lights directly)
    func lights(forZone zone: Zone) -> [HueLight] {
        let lightIds = Set(zone.children.filter { $0.rtype == "light" }.map(\.rid))
        return lights.filter { lightIds.contains($0.id) }
    }

    /// Validate that a resource ID matches the expected Hue API UUID format
    private static func isValidResourceId(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
    }

    /// Toggle a grouped light on/off
    func toggleGroupedLight(id: String, on: Bool) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        let memberLightIds = lightIds(inGroupedLight: id)
        applyGroupedLightOnOptimistically(id: id, on: on)
        optimisticallyUpdateLights(withIds: memberLightIds, on: on)

        do {
            try await sendControlRequest(
                path: "grouped_light/\(id)",
                operation: .toggle,
                body: try JSONEncoder().encode(["on": OnState(on: on)])
            )
        } catch {
            // Revert on failure
            clearOptimisticGroupedLightToggle(id: id)
            clearOptimisticLightToggles(withIds: memberLightIds)
            await reconcileControlFailure {
                groupedLights = try await fetchGroupedLights()
                if !memberLightIds.isEmpty {
                    lights = try await fetchLights()
                }
            }
            throw error
        }
    }

    func previewBrightness(groupedLightId: String, brightness: Double) {
        guard Self.isValidResourceId(groupedLightId) else { return }
        applyGroupedLightBrightnessOptimistically(id: groupedLightId, brightness: brightness)
    }

    /// Set brightness for a grouped light (0.0–100.0)
    func setBrightness(groupedLightId: String, brightness: Double) async throws {
        guard Self.isValidResourceId(groupedLightId) else {
            throw HueAPIError.invalidResourceId
        }
        let clampedBrightness = applyGroupedLightBrightnessOptimistically(id: groupedLightId, brightness: brightness)

        do {
            try await sendControlRequest(
                path: "grouped_light/\(groupedLightId)",
                operation: .brightness,
                body: try JSONEncoder().encode(["dimming": DimmingState(brightness: clampedBrightness)])
            )
        } catch {
            // Revert on failure
            optimisticUpdates.clear(.brightness, for: .groupedLight, id: groupedLightId)
            await reconcileControlFailure { groupedLights = try await fetchGroupedLights() }
            throw error
        }
    }

    func previewGroupedLightColorTemperature(id: String, mirek: Int) {
        guard Self.isValidResourceId(id) else { return }
        applyGroupedLightColorTemperatureOptimistically(id: id, mirek: mirek)
    }

    /// Set color temperature for a grouped light (153–500 mirek)
    func setGroupedLightColorTemperature(id: String, mirek: Int) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        let clamped = applyGroupedLightColorTemperatureOptimistically(id: id, mirek: mirek)

        do {
            let body = try JSONEncoder().encode(["color_temperature": ["mirek": clamped]])
            try await sendControlRequest(path: "grouped_light/\(id)", operation: .colorTemperature, body: body)
        } catch {
            optimisticUpdates.clear(.colorTemperature, for: .groupedLight, id: id)
            await reconcileControlFailure { groupedLights = try await fetchGroupedLights() }
            throw error
        }
    }

    @discardableResult
    func previewGroupedLightColor(lightIds: [String], xy: CIEXYColor) -> UUID {
        let token = UUID()
        for lightId in lightIds {
            let original: LightColor?
            if let pending = groupColorPreviews[lightId] {
                original = pending.original
            } else {
                original = lights.first(where: { $0.id == lightId })?.color
            }
            previewLightColor(id: lightId, xy: xy)
            groupColorPreviews[lightId] = GroupColorPreview(token: token, original: original)
        }
        return token
    }

    /// Set color for every light in a grouped light using CIE xy coordinates.
    /// `lightIds` are the group's color-capable lights, updated optimistically so their cards follow.
    func setGroupedLightColor(id: String, xy: CIEXYColor, lightIds: [String], previewToken: UUID? = nil) async throws {
        let token = previewToken ?? previewGroupedLightColor(lightIds: lightIds, xy: xy)
        do {
            guard Self.isValidResourceId(id) else {
                throw HueAPIError.invalidResourceId
            }
            let body = try JSONEncoder().encode(["color": ["xy": ["x": xy.x, "y": xy.y]]])
            try await sendControlRequest(path: "grouped_light/\(id)", operation: .color, body: body)
            for lightId in lightIds {
                if groupColorPreviews[lightId]?.token == token {
                    groupColorPreviews[lightId] = nil
                } else if groupColorPreviews[lightId] != nil {
                    groupColorPreviews[lightId]?.original = LightColor(xy: xy)
                }
            }
        } catch {
            for lightId in lightIds where groupColorPreviews[lightId]?.token == token {
                optimisticUpdates.clear(.color, for: .light, id: lightId)
                if let index = lights.firstIndex(where: { $0.id == lightId }) {
                    lights[index].color = groupColorPreviews[lightId]?.original
                }
            }
            // A failed/cancelled PUT may still have reached the bridge. Reconcile independently
            // of caller cancellation, without overwriting newer previews or unrelated fields.
            do {
                let refreshed = try await Task { try await self.fetchLights() }.value
                for light in refreshed where groupColorPreviews[light.id]?.token == token {
                    if let index = lights.firstIndex(where: { $0.id == light.id }) {
                        lights[index].color = light.color
                    }
                }
            } catch {
                logFailure("Failed to reconcile group color: \(Self.safeFailureCategory(error))")
            }
            for lightId in lightIds where groupColorPreviews[lightId]?.token == token {
                groupColorPreviews[lightId] = nil
            }
            throw error
        }
    }

    /// Look up the GroupedLight for a room or zone
    func groupedLight(for groupId: String?) -> GroupedLight? {
        guard let groupId else { return nil }
        return groupedLights.first(where: { $0.id == groupId })
    }

    /// Filter scenes belonging to a specific room or zone
    func scenes(for groupId: String?) -> [HueScene] {
        guard let groupId else { return [] }
        return scenes.filter { $0.group.rid == groupId }
    }

    /// Find the active scene for a room/zone by checking scene status from the API
    func activeScene(for groupId: String?) -> HueScene? {
        guard let groupId else { return nil }
        // Check scenes where the API reports active, static, or dynamic_palette status
        if let active = scenes.first(where: {
            $0.group.rid == groupId && ($0.status?.active == .active || $0.status?.active == .static || $0.status?.active == .dynamicPalette)
        }) {
            return active
        }
        // Fall back to our locally tracked active scene
        if let activeId = activeSceneId {
            return scenes.first(where: { $0.id == activeId && $0.group.rid == groupId })
        }
        return nil
    }

    /// Get the raw palette entries for a room/zone card.
    /// Prefers current on-light state, falls back only to a known active scene.
    func previewPaletteEntries(for groupId: String?) -> [ScenePaletteEntry] {
        guard let groupId else { return [] }
        let currentEntries = currentLightPaletteEntries(for: groupId)
        if !currentEntries.isEmpty {
            return currentEntries
        }

        if let active = activeScene(for: groupId), !active.paletteEntries.isEmpty {
            return active.paletteEntries
        }

        return []
    }

    private func currentLightPaletteEntries(for groupId: String) -> [ScenePaletteEntry] {
        lights(forGroupId: groupId).compactMap { light in
            guard light.isOn else { return nil }
            if let xy = light.color?.xy {
                return .xy(xy, brightness: light.dimming?.brightness)
            }
            if let mirek = light.colorTemperature?.mirek {
                return .colorTemperature(mirek: mirek, brightness: light.dimming?.brightness)
            }
            if light.dimming != nil {
                return .colorTemperature(mirek: Self.defaultWarmWhiteMirek, brightness: light.dimming?.brightness)
            }
            return nil
        }
    }

    private func lights(forGroupId groupId: String) -> [HueLight] {
        if let room = rooms.first(where: { $0.id == groupId }) {
            return lights(forRoom: room)
        }
        if let zone = zones.first(where: { $0.id == groupId }) {
            return lights(forZone: zone)
        }
        return []
    }

    /// Recall (activate) a scene, optionally in dynamic palette mode
    func recallScene(id: String, dynamic: Bool = false) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        let previousSceneId = activeSceneId
        let previousIsDynamic = activeSceneIsDynamic
        let previousStatus = scenes.first(where: { $0.id == id })?.status
        activeSceneId = id
        activeSceneIsDynamic = dynamic
        // Optimistically update scene status so isActiveSceneDynamic reflects the change immediately
        let optimisticStatus = HueSceneStatus(active: dynamic ? .dynamicPalette : .active)
        updateSceneStatus(id: id, status: optimisticStatus)
        let action = dynamic ? "dynamic_palette" : "active"
        do {
            try await sendSceneRecall(id: id, action: action)
        } catch {
            // Rollback optimistic update
            activeSceneId = previousSceneId
            activeSceneIsDynamic = previousIsDynamic
            updateSceneStatus(id: id, status: previousStatus)
            throw error
        }
        // Refresh grouped lights to reflect scene's brightness/on state
        groupedLights = try await fetchGroupedLights()
    }

    /// Set the speed for a dynamic scene (0.0–1.0)
    func setSceneSpeed(id: String, speed: Double) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        let clamped = min(max(speed, 0.0), 1.0)
        let isDynamicSceneLive = isSceneDynamicActive(id: id)

        // Save previous speed for rollback
        let previousSpeed = scenes.first(where: { $0.id == id })?.speed

        // Optimistic update
        updateSceneSpeed(id: id, speed: clamped)

        do {
            let body = try JSONEncoder().encode(["speed": clamped])
            try await sendControlRequest(path: "scene/\(id)", operation: .speed, body: body)
        } catch {
            // Rollback optimistic update
            if let previousSpeed {
                updateSceneSpeed(id: id, speed: previousSpeed)
            }
            throw error
        }

        if isDynamicSceneLive {
            try await sendSceneRecall(id: id, action: "dynamic_palette")
        }
    }

    /// Whether the active scene for a group is in dynamic palette mode
    func isActiveSceneDynamic(for groupId: String?) -> Bool {
        guard let scene = activeScene(for: groupId) else { return false }
        return isSceneDynamicActive(scene)
    }

    private func sendSceneRecall(id: String, action: String) async throws {
        let body = try JSONEncoder().encode(["recall": ["action": action]])
        try await sendControlRequest(path: "scene/\(id)", operation: .recall, body: body)
    }

    private func isSceneDynamicActive(id: String) -> Bool {
        guard let scene = scenes.first(where: { $0.id == id }) else {
            return activeSceneId == id && activeSceneIsDynamic
        }
        return isSceneDynamicActive(scene)
    }

    private func isSceneDynamicActive(_ scene: HueScene) -> Bool {
        if scene.isDynamicActive { return true }
        // Fall back to locally tracked state.
        return activeSceneId == scene.id && activeSceneIsDynamic
    }

    private func updateSceneSpeed(id: String, speed: Double) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        scenes[index].speed = speed
    }

    private func updateSceneStatus(id: String, status: HueSceneStatus?) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        scenes[index].status = status
    }

    // MARK: - Event Stream (SSE)

    private var eventStreamConnection: EventStreamConnection?
    private var eventConsumingTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var optimisticUpdates = OptimisticUpdateTracker()

    func startEventStream() {
        guard eventConsumingTask == nil else { return }

        let connection = eventStreamConnection ?? EventStreamConnection(
            bridgeIP: bridgeIP,
            applicationKey: applicationKey,
            session: session
        )
        eventStreamConnection = connection

        let stream = connection.start()
        eventConsumingTask = Task { [weak self] in
            for await message in stream {
                await self?.handleEventStreamMessage(message)
            }
        }
    }

    func stopEventStream() {
        eventStreamConnection?.stop()
        eventConsumingTask?.cancel()
        refreshDebounceTask?.cancel()
        eventStreamConnection = nil
        eventConsumingTask = nil
        refreshDebounceTask = nil
    }

    func handleEventStreamMessage(_ message: EventStreamMessage) async {
        switch message {
        case .reconnected:
            // The full refresh supersedes a pending debounced one. Waiting for it to finish keeps its
            // older snapshot from landing after ours.
            if let pendingRefresh = refreshDebounceTask {
                refreshDebounceTask = nil
                pendingRefresh.cancel()
                await pendingRefresh.value
                guard !Task.isCancelled else { return }
            }
            await fetchAll()
        case .events(let events):
            applyEvents(events)
        }
    }

    func applyEvents(_ events: [HueEvent]) {
        for event in events {
            switch event.type {
            case .update:
                for resource in event.data {
                    switch resource.type {
                    case "grouped_light":
                        let filteredResource = optimisticUpdates.filter(resource, kind: .groupedLight)
                        EventStreamUpdater.apply(filteredResource, to: &groupedLights)
                    case "light":
                        let filteredResource = optimisticUpdates.filter(resource, kind: .light)
                        EventStreamUpdater.apply(filteredResource, to: &lights)
                        if filteredResource.on != nil {
                            syncGroupedLightOnState(containingLightId: resource.id)
                        }
                    case "scene":
                        if let status = resource.status?.active,
                           let resourceStatus = resource.status {
                            if status == .static || status == .active {
                                activeSceneId = resource.id
                                activeSceneIsDynamic = false
                            } else if status == .dynamicPalette {
                                activeSceneId = resource.id
                                activeSceneIsDynamic = true
                            } else if status == .inactive, activeSceneId == resource.id {
                                activeSceneId = nil
                                activeSceneIsDynamic = false
                            }
                            updateSceneStatus(id: resource.id, status: resourceStatus)
                        }
                        if let speed = resource.speed {
                            updateSceneSpeed(id: resource.id, speed: speed)
                        }
                    default:
                        break
                    }
                }
            case .add, .delete:
                refreshDebounceTask?.cancel()
                refreshDebounceTask = Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled else { return }
                    await fetchAll()
                }
            }
        }
    }

    /// Derives each containing group's on state from its member lights. It is skipped while the user's
    /// own toggle of that group is pending, because the derived value could coincidentally match and
    /// end the protection before the bridge's own `grouped_light` event arrives.
    private func syncGroupedLightOnState(containingLightId lightId: String) {
        for groupedLightId in groupedLightIds(containingLightId: lightId) {
            guard !optimisticUpdates.hasPending(.on, for: .groupedLight, id: groupedLightId) else { continue }
            let memberLights = lights(inGroupedLight: groupedLightId)
            guard !memberLights.isEmpty else { continue }
            let derivedState = HueEventResource(
                id: groupedLightId,
                type: "grouped_light",
                on: OnState(on: memberLights.contains(where: \.isOn)),
                dimming: nil,
                color: nil,
                colorTemperature: nil,
                status: nil,
                metadata: nil,
                speed: nil
            )
            EventStreamUpdater.apply(derivedState, to: &groupedLights)
        }
    }

    private func groupedLightIds(containingLightId lightId: String) -> Set<String> {
        var groupedLightIds = Set<String>()
        for room in rooms where lights(forRoom: room).contains(where: { $0.id == lightId }) {
            if let groupedLightId = room.groupedLightId {
                groupedLightIds.insert(groupedLightId)
            }
        }
        for zone in zones where lights(forZone: zone).contains(where: { $0.id == lightId }) {
            if let groupedLightId = zone.groupedLightId {
                groupedLightIds.insert(groupedLightId)
            }
        }
        return groupedLightIds
    }

    private func lights(inGroupedLight groupedLightId: String) -> [HueLight] {
        if let room = rooms.first(where: { $0.groupedLightId == groupedLightId }) {
            return lights(forRoom: room)
        }
        if let zone = zones.first(where: { $0.groupedLightId == groupedLightId }) {
            return lights(forZone: zone)
        }
        return []
    }

    // MARK: - Pinning & Ordering (forwarded to RoomOrderManager)

    var pinnedRoomIds: Set<String> { orderManager.pinnedRoomIds }
    var pinnedZoneIds: Set<String> { orderManager.pinnedZoneIds }

    func isRoomPinned(_ id: String) -> Bool { orderManager.isRoomPinned(id) }
    func isZonePinned(_ id: String) -> Bool { orderManager.isZonePinned(id) }

    func toggleRoomPin(_ id: String) { orderManager.toggleRoomPin(id, rooms: &rooms) }
    func toggleZonePin(_ id: String) { orderManager.toggleZonePin(id, zones: &zones) }

    func moveRoom(fromId: String, toId: String) { orderManager.moveRoom(fromId: fromId, toId: toId, rooms: &rooms) }
    func moveZone(fromId: String, toId: String) { orderManager.moveZone(fromId: fromId, toId: toId, zones: &zones) }

    func moveRoomToTop(_ id: String) { orderManager.moveRoomToTop(id: id, rooms: &rooms) }
    func moveRoomToBottom(_ id: String) { orderManager.moveRoomToBottom(id: id, rooms: &rooms) }
    func moveZoneToTop(_ id: String) { orderManager.moveZoneToTop(id: id, zones: &zones) }
    func moveZoneToBottom(_ id: String) { orderManager.moveZoneToBottom(id: id, zones: &zones) }

    // MARK: - Private

    private func applyLightOnOptimistically(id: String, on: Bool) {
        optimisticUpdates.record(.on(on), for: .light, id: id)
        if let index = lights.firstIndex(where: { $0.id == id }) {
            lights[index].on = OnState(on: on)
        }
    }

    @discardableResult
    private func applyLightBrightnessOptimistically(id: String, brightness: Double) -> Double {
        let clamped = clampBrightness(brightness)
        optimisticUpdates.record(.brightness(clamped), for: .light, id: id)
        if let index = lights.firstIndex(where: { $0.id == id }) {
            lights[index].dimming = DimmingState(brightness: clamped)
        }
        return clamped
    }

    private func applyLightColorOptimistically(id: String, xy: CIEXYColor) {
        groupColorPreviews[id] = nil
        optimisticUpdates.record(.color(xy), for: .light, id: id)
        if let index = lights.firstIndex(where: { $0.id == id }) {
            lights[index].color = LightColor(xy: xy)
        }
    }

    @discardableResult
    private func applyLightColorTemperatureOptimistically(id: String, mirek: Int) -> Int {
        let clamped = clampMirek(mirek)
        optimisticUpdates.record(.colorTemperature(clamped), for: .light, id: id)
        if let index = lights.firstIndex(where: { $0.id == id }) {
            lights[index].colorTemperature = LightColorTemperature(mirek: clamped, mirekValid: true)
        }
        return clamped
    }

    private func applyGroupedLightOnOptimistically(id: String, on: Bool) {
        optimisticUpdates.record(.on(on), for: .groupedLight, id: id)
        if let index = groupedLights.firstIndex(where: { $0.id == id }) {
            groupedLights[index].on = OnState(on: on)
        }
    }

    private func optimisticallyUpdateLights(withIds lightIds: Set<String>, on: Bool) {
        guard !lightIds.isEmpty else { return }

        for index in lights.indices where lightIds.contains(lights[index].id) {
            let lightId = lights[index].id
            optimisticUpdates.record(.on(on), for: .light, id: lightId)
            lights[index].on = OnState(on: on)
        }
    }

    private func lightIds(inGroupedLight groupedLightId: String) -> Set<String> {
        var lightIds = Set<String>()

        for room in rooms where room.groupedLightId == groupedLightId {
            lightIds.formUnion(lights(forRoom: room).map(\.id))
        }

        for zone in zones where zone.groupedLightId == groupedLightId {
            lightIds.formUnion(lights(forZone: zone).map(\.id))
        }

        return lightIds
    }

    private func clearOptimisticLightToggle(id: String) {
        optimisticUpdates.clear(.on, for: .light, id: id)
    }

    private func clearOptimisticGroupedLightToggle(id: String) {
        optimisticUpdates.clear(.on, for: .groupedLight, id: id)
    }

    private func clearOptimisticLightToggles(withIds lightIds: Set<String>) {
        for lightId in lightIds {
            clearOptimisticLightToggle(id: lightId)
        }
    }

    @discardableResult
    private func applyGroupedLightBrightnessOptimistically(id: String, brightness: Double) -> Double {
        let clamped = clampBrightness(brightness)
        optimisticUpdates.record(.brightness(clamped), for: .groupedLight, id: id)
        if let index = groupedLights.firstIndex(where: { $0.id == id }) {
            groupedLights[index].dimming = DimmingState(brightness: clamped)
        }
        return clamped
    }

    @discardableResult
    private func applyGroupedLightColorTemperatureOptimistically(id: String, mirek: Int) -> Int {
        let clamped = clampMirek(mirek)
        optimisticUpdates.record(.colorTemperature(clamped), for: .groupedLight, id: id)
        if let index = groupedLights.firstIndex(where: { $0.id == id }) {
            groupedLights[index].colorTemperature = LightColorTemperature(mirek: clamped, mirekValid: true)
        }
        return clamped
    }

    private func clampBrightness(_ brightness: Double) -> Double {
        min(max(brightness, 0.0), 100.0)
    }

    private func clampMirek(_ mirek: Int) -> Int {
        min(max(mirek, 153), 500)
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/clip/v2/resource/\(path)"
        guard let url = components.url else {
            throw HueAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(applicationKey, forHTTPHeaderField: "hue-application-key")
        if method == "PUT" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func reconcileControlFailure(_ refresh: () async throws -> Void) async {
        do {
            try await refresh()
        } catch {
            logFailure("Failed to refresh state after control request failure: \(Self.safeFailureCategory(error))")
        }
    }

    private static func safeFailureCategory(_ error: any Error) -> String {
        if let urlError = error as? URLError {
            return "transport (URL error \(urlError.code.rawValue))"
        }
        if error is DecodingError { return "decode response" }
        if let apiError = error as? HueAPIError {
            switch apiError {
            case .bridgeError: return "bridge API"
            case .invalidResponse: return "invalid response"
            case .invalidResourceId: return "invalid resource identifier"
            case .invalidBridgeIP: return "invalid bridge address"
            }
        }
        return "request failure"
    }

    /// Log only locally generated diagnostics: URLs, headers, bodies, and error descriptions may contain secrets.
    private func sendControlRequest(path: String, operation: ControlOperation, body: Data) async throws {
        let resource = String(path.prefix(while: { $0 != "/" }))
        var failure = "request setup"
        do {
            let request = try makeRequest(path: path, method: "PUT", body: body)
            failure = "transport"
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                failure = "HTTP \(httpResponse.statusCode)"
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw HueAPIError.invalidResponse
                }
            } else {
                failure = "non-HTTP response"
                throw HueAPIError.invalidResponse
            }
            if !data.isEmpty {
                failure = "decode response"
                let result = try JSONDecoder().decode(HueResponse<ResourceLink>.self, from: data)
                if let error = result.errors.first {
                    failure = "bridge API (\(result.errors.count) errors)"
                    throw HueAPIError.bridgeError(error.description)
                }
            }
        } catch {
            if let urlError = error as? URLError {
                failure = "transport (URL error \(urlError.code.rawValue))"
            }
            logFailure("PUT \(resource) \(operation.rawValue) failed: \(failure)")
            throw error
        }
    }

    private func fetch<T: Decodable & Sendable>(path: String) async throws -> [T] {
        let request = try makeRequest(path: path)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HueAPIError.invalidResponse
        }
        let hueResponse = try JSONDecoder().decode(HueResponse<T>.self, from: data)

        if let first = hueResponse.errors.first {
            throw HueAPIError.bridgeError(first.description)
        }

        return hueResponse.data
    }
}
