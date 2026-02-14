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
    var isLoading: Bool = false
    var lastError: String?

    let orderManager = RoomOrderManager()

    // Internal access so extensions in separate files can use these
    let bridgeIP: String
    let applicationKey: String
    let session: URLSession
    var eventStreamTask: Task<Void, Never>?

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
    static func isValidResourceId(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
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

    func makeRequest(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
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

    func fetch<T: Decodable & Sendable>(path: String) async throws -> [T] {
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
