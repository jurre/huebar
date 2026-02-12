import Foundation
import SwiftUI

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
                color: light.color, color_temperature: light.color_temperature
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
                color: light.color, color_temperature: light.color_temperature
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
        let uuidRegex = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/
        return id.wholeMatch(of: uuidRegex) != nil
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
                dimming: groupedLights[index].dimming
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
                dimming: DimmingState(brightness: clampedBrightness)
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
        // Check scenes where the API reports active status
        if let active = scenes.first(where: {
            $0.group.rid == groupId && $0.status?.active == "active"
        }) {
            return active
        }
        // Fall back to our locally tracked active scene
        if let activeId = activeSceneId {
            return scenes.first(where: { $0.id == activeId && $0.group.rid == groupId })
        }
        return nil
    }

    /// Get the palette colors for display on a room/zone card.
    /// Prefers the active scene, falls back to the first scene with palette colors.
    func activeSceneColors(for groupId: String?) -> [Color] {
        guard let groupId else { return [] }
        // Use active scene if we know it
        if let active = activeScene(for: groupId), !active.paletteColors.isEmpty {
            return active.paletteColors
        }
        // Fall back: use the first scene for this group that has palette colors
        let groupScenes = scenes.filter { $0.group.rid == groupId }
        if let withPalette = groupScenes.first(where: { !$0.paletteColors.isEmpty }) {
            return withPalette.paletteColors
        }
        return []
    }

    /// Recall (activate) a scene
    func recallScene(id: String) async throws {
        guard Self.isValidResourceId(id) else {
            throw HueAPIError.invalidResourceId
        }
        activeSceneId = id
        let body = try JSONEncoder().encode(["recall": ["action": "active"]])
        let request = try makeRequest(path: "scene/\(id)", method: "PUT", body: body)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HueAPIError.invalidResponse
        }
        // Refresh grouped lights to reflect scene's brightness/on state
        groupedLights = try await fetchGroupedLights()
    }

    // MARK: - Event Stream (SSE)

    private var eventStreamTask: Task<Void, Never>?

    func startEventStream() {
        guard eventStreamTask == nil else { return }
        eventStreamTask = Task { await runEventStream() }
    }

    func stopEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
    }

    private func runEventStream() async {
        let parser = SSEParser()
        var backoff: UInt64 = 1

        while !Task.isCancelled {
            parser.reset()

            do {
                var components = URLComponents()
                components.scheme = "https"
                components.host = bridgeIP
                components.path = "/eventstream/clip/v2"
                guard let url = components.url else { continue }

                var request = URLRequest(url: url)
                request.setValue(applicationKey, forHTTPHeaderField: "hue-application-key")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                let (bytes, response) = try await session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { throw HueAPIError.invalidResponse }

                backoff = 1

                var lineBuffer = Data()
                for try await byte in bytes {
                    if byte == UInt8(ascii: "\n") {
                        let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                        lineBuffer.removeAll(keepingCapacity: true)
                        if let events = parser.processLine(line) {
                            applyEvents(events)
                        }
                    } else {
                        lineBuffer.append(byte)
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                // Sleep with exponential backoff before retrying
                do {
                    try await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                } catch { break }
                backoff = min(backoff * 2, 30)
            }
        }
    }

    private func applyEvents(_ events: [HueEvent]) {
        for event in events {
            switch event.type {
            case .update:
                for resource in event.data {
                    switch resource.resourceType {
                    case "grouped_light":
                        EventStreamUpdater.apply(resource, to: &groupedLights)
                    case "light":
                        EventStreamUpdater.apply(resource, to: &lights)
                    case "scene":
                        if resource.status?.active == "static" {
                            activeSceneId = resource.id
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
