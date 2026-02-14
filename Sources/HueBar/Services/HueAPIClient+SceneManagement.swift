import Foundation

extension HueAPIClient {

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
            $0.group.rid == groupId && $0.status?.active == .active
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
}
