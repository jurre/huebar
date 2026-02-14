import Foundation
import Observation

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

    private let bridgeIP: String
    private let applicationKey: String
    private let session: URLSession

    init(bridgeIP: String, applicationKey: String) throws {
        guard IPValidation.isValid(bridgeIP) else {
            throw HueAPIError.invalidBridgeIP
        }
        self.bridgeIP = bridgeIP
        self.applicationKey = applicationKey
        let config = URLSessionConfiguration.default
        self.session = URLSession(
            configuration: config,
            delegate: HueBridgeTrustDelegate(bridgeIP: bridgeIP),
            delegateQueue: nil
        )
    }

    // Internal init for testing with a custom URLSession
    init(bridgeIP: String, applicationKey: String, session: URLSession) {
        self.bridgeIP = bridgeIP
        self.applicationKey = applicationKey
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
        // Optimistic update
        if let index = lights.firstIndex(where: { $0.id == id }) {
            let light = lights[index]
            lights[index] = HueLight(
                id: id, owner: light.owner, metadata: light.metadata,
                on: OnState(on: on), dimming: light.dimming,
                color: light.color, colorTemperature: light.colorTemperature
            )
        }

        let request = try makeRequest(
            path: "light/\(id)",
            method: "PUT",
            body: try JSONEncoder().encode(["on": OnState(on: on)])
        )
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            lights = try await fetchLights()
            throw HueAPIError.invalidResponse
        }
    }

    /// Set brightness for an individual light (0.0–100.0)
    func setLightBrightness(id: String, brightness: Double) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        let clamped = min(max(brightness, 0.0), 100.0)

        if let index = lights.firstIndex(where: { $0.id == id }) {
            let light = lights[index]
            lights[index] = HueLight(
                id: id, owner: light.owner, metadata: light.metadata,
                on: light.on, dimming: DimmingState(brightness: clamped),
                color: light.color, colorTemperature: light.colorTemperature
            )
        }

        let request = try makeRequest(
            path: "light/\(id)",
            method: "PUT",
            body: try JSONEncoder().encode(["dimming": DimmingState(brightness: clamped)])
        )
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            lights = try await fetchLights()
            throw HueAPIError.invalidResponse
        }
    }

    /// Set color for an individual light using CIE xy coordinates
    func setLightColor(id: String, xy: CIEXYColor) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }

        // Optimistic update
        if let index = lights.firstIndex(where: { $0.id == id }) {
            let light = lights[index]
            lights[index] = HueLight(
                id: id, owner: light.owner, metadata: light.metadata,
                on: light.on, dimming: light.dimming,
                color: LightColor(xy: xy), colorTemperature: light.colorTemperature
            )
        }

        let body = try JSONEncoder().encode(["color": ["xy": ["x": xy.x, "y": xy.y]]])
        let request = try makeRequest(path: "light/\(id)", method: "PUT", body: body)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            lights = try await fetchLights()
            throw HueAPIError.invalidResponse
        }
    }

    /// Set color temperature for an individual light (mirek value: 153–500)
    func setLightColorTemperature(id: String, mirek: Int) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        let clampedMirek = min(max(mirek, 153), 500)

        // Optimistic update
        if let index = lights.firstIndex(where: { $0.id == id }) {
            let light = lights[index]
            lights[index] = HueLight(
                id: id, owner: light.owner, metadata: light.metadata,
                on: light.on, dimming: light.dimming,
                color: light.color, colorTemperature: LightColorTemperature(mirek: clampedMirek, mirekValid: true)
            )
        }

        let body = try JSONEncoder().encode(["color_temperature": ["mirek": clampedMirek]])
        let request = try makeRequest(path: "light/\(id)", method: "PUT", body: body)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            lights = try await fetchLights()
            throw HueAPIError.invalidResponse
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
        // Optimistically update local state so the toggle reflects immediately
        if let index = groupedLights.firstIndex(where: { $0.id == id }) {
            groupedLights[index] = GroupedLight(
                id: id,
                on: OnState(on: on),
                dimming: groupedLights[index].dimming,
                colorTemperature: groupedLights[index].colorTemperature
            )
        }

        let request = try makeRequest(
            path: "grouped_light/\(id)",
            method: "PUT",
            body: try JSONEncoder().encode(["on": OnState(on: on)])
        )
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Revert on failure
            groupedLights = try await fetchGroupedLights()
            throw HueAPIError.invalidResponse
        }
    }

    /// Set brightness for a grouped light (0.0–100.0)
    func setBrightness(groupedLightId: String, brightness: Double) async throws {
        guard Self.isValidResourceId(groupedLightId) else {
            throw HueAPIError.invalidResourceId
        }
        let clampedBrightness = min(max(brightness, 0.0), 100.0)

        // Optimistic update
        if let index = groupedLights.firstIndex(where: { $0.id == groupedLightId }) {
            groupedLights[index] = GroupedLight(
                id: groupedLightId,
                on: groupedLights[index].on,
                dimming: DimmingState(brightness: clampedBrightness),
                colorTemperature: groupedLights[index].colorTemperature
            )
        }

        let request = try makeRequest(
            path: "grouped_light/\(groupedLightId)",
            method: "PUT",
            body: try JSONEncoder().encode(["dimming": DimmingState(brightness: clampedBrightness)])
        )
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Revert on failure
            groupedLights = try await fetchGroupedLights()
            throw HueAPIError.invalidResponse
        }
    }

    /// Set color temperature for a grouped light (153–500 mirek)
    func setGroupedLightColorTemperature(id: String, mirek: Int) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        let clamped = min(max(mirek, 153), 500)

        if let index = groupedLights.firstIndex(where: { $0.id == id }) {
            groupedLights[index] = GroupedLight(
                id: id,
                on: groupedLights[index].on,
                dimming: groupedLights[index].dimming,
                colorTemperature: LightColorTemperature(mirek: clamped, mirekValid: true)
            )
        }

        let body = try JSONEncoder().encode(["color_temperature": ["mirek": clamped]])
        let request = try makeRequest(path: "grouped_light/\(id)", method: "PUT", body: body)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            groupedLights = try await fetchGroupedLights()
            throw HueAPIError.invalidResponse
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
    /// Prefers the active scene, falls back to the first scene with palette entries.
    func activeScenePaletteEntries(for groupId: String?) -> [ScenePaletteEntry] {
        guard let groupId else { return [] }
        // Use active scene if we know it
        if let active = activeScene(for: groupId), !active.paletteEntries.isEmpty {
            return active.paletteEntries
        }
        // Fall back: use the first scene for this group that has palette entries
        let groupScenes = scenes.filter { $0.group.rid == groupId }
        if let withPalette = groupScenes.first(where: { !$0.paletteEntries.isEmpty }) {
            return withPalette.paletteEntries
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
        activeSceneId = id
        activeSceneIsDynamic = dynamic
        let action = dynamic ? "dynamic_palette" : "active"
        let body = try JSONEncoder().encode(["recall": ["action": action]])
        let request = try makeRequest(path: "scene/\(id)", method: "PUT", body: body)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Rollback optimistic update
            activeSceneId = previousSceneId
            activeSceneIsDynamic = previousIsDynamic
            throw HueAPIError.invalidResponse
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

        // Save previous speed for rollback
        let previousSpeed = scenes.first(where: { $0.id == id })?.speed

        // Optimistic update
        updateSceneSpeed(id: id, speed: clamped)

        let body = try JSONEncoder().encode(["speed": clamped])
        let request = try makeRequest(path: "scene/\(id)", method: "PUT", body: body)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Rollback optimistic update
            if let previousSpeed {
                updateSceneSpeed(id: id, speed: previousSpeed)
            }
            throw HueAPIError.invalidResponse
        }
    }

    /// Whether the active scene for a group is in dynamic palette mode
    func isActiveSceneDynamic(for groupId: String?) -> Bool {
        guard let scene = activeScene(for: groupId) else { return false }
        if scene.isDynamicActive { return true }
        // Fall back to locally tracked state
        return scene.id == activeSceneId && activeSceneIsDynamic
    }

    private func updateSceneSpeed(id: String, speed: Double) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        let scene = scenes[index]
        scenes[index] = HueScene(
            id: scene.id,
            type: scene.type,
            metadata: scene.metadata,
            group: scene.group,
            status: scene.status,
            palette: scene.palette,
            speed: speed,
            autoDynamic: scene.autoDynamic
        )
    }

    private func updateSceneStatus(id: String, status: HueSceneStatus) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        let scene = scenes[index]
        scenes[index] = HueScene(
            id: scene.id,
            type: scene.type,
            metadata: scene.metadata,
            group: scene.group,
            status: status,
            palette: scene.palette,
            speed: scene.speed,
            autoDynamic: scene.autoDynamic
        )
    }

    // MARK: - Event Stream (SSE)

    private var eventStreamConnection: EventStreamConnection?
    private var eventConsumingTask: Task<Void, Never>?

    func startEventStream() {
        guard eventConsumingTask == nil else { return }

        let connection = eventStreamConnection ?? EventStreamConnection(
            bridgeIP: bridgeIP,
            applicationKey: applicationKey,
            session: session
        )
        eventStreamConnection = connection

        let stream = connection.start()
        eventConsumingTask = Task {
            for await events in stream {
                applyEvents(events)
            }
        }
    }

    func stopEventStream() {
        eventStreamConnection?.stop()
        eventConsumingTask?.cancel()
        eventStreamConnection = nil
        eventConsumingTask = nil
    }

    private func applyEvents(_ events: [HueEvent]) {
        for event in events {
            switch event.type {
            case .update:
                for resource in event.data {
                    switch resource.type {
                    case "grouped_light":
                        EventStreamUpdater.apply(resource, to: &groupedLights)
                    case "light":
                        EventStreamUpdater.apply(resource, to: &lights)
                    case "scene":
                        if let status = resource.status?.active {
                            if status == .static || status == .active {
                                activeSceneId = resource.id
                                activeSceneIsDynamic = false
                            } else if status == .dynamicPalette {
                                activeSceneId = resource.id
                                activeSceneIsDynamic = true
                            }
                            updateSceneStatus(id: resource.id, status: resource.status!)
                        }
                        if let speed = resource.speed {
                            updateSceneSpeed(id: resource.id, speed: speed)
                        }
                    default:
                        break
                    }
                }
            case .add, .delete:
                Task { await fetchAll() }
            }
        }
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

    // MARK: - Private

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = bridgeIP
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
