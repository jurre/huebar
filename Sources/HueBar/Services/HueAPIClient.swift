import Foundation

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
    var isLoading: Bool = false
    var lastError: String?

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

            let (r, z, g) = try await (fetchedRooms, fetchedZones, fetchedGroupedLights)
            rooms = applySavedOrder(r, key: Self.roomOrderKey)
            zones = applySavedOrder(z, key: Self.zoneOrderKey)
            groupedLights = g
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

    /// Look up the GroupedLight for a room or zone
    func groupedLight(for groupId: String?) -> GroupedLight? {
        guard let groupId else { return nil }
        return groupedLights.first(where: { $0.id == groupId })
    }

    // MARK: - Ordering

    private static let roomOrderKey = "huebar.roomOrder"
    private static let zoneOrderKey = "huebar.zoneOrder"

    func moveRoom(fromId: String, toId: String) {
        reorder(&rooms, fromId: fromId, toId: toId)
        saveOrder(rooms, key: Self.roomOrderKey)
    }

    func moveZone(fromId: String, toId: String) {
        reorder(&zones, fromId: fromId, toId: toId)
        saveOrder(zones, key: Self.zoneOrderKey)
    }

    private func reorder<T: Identifiable>(_ items: inout [T], fromId: String, toId: String) where T.ID == String {
        guard let fromIndex = items.firstIndex(where: { $0.id == fromId }),
              let toIndex = items.firstIndex(where: { $0.id == toId }),
              fromIndex != toIndex else { return }
        let item = items.remove(at: fromIndex)
        items.insert(item, at: toIndex)
    }

    private func saveOrder<T: Identifiable>(_ items: [T], key: String) where T.ID == String {
        UserDefaults.standard.set(items.map(\.id), forKey: key)
    }

    private func applySavedOrder<T: Identifiable>(_ items: [T], key: String) -> [T] where T.ID == String {
        guard let savedOrder = UserDefaults.standard.stringArray(forKey: key) else { return items }
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let ordered = savedOrder.compactMap { lookup[$0] }
        let remaining = items.filter { !savedOrder.contains($0.id) }
        return ordered + remaining
    }

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
