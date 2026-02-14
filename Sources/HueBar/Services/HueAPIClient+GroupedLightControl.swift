import Foundation

extension HueAPIClient {

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
}
