import Foundation

extension HueAPIClient {

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
}
