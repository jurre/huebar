import Foundation

enum EventStreamUpdater {
    static func apply(_ event: HueEventResource, to groupedLights: inout [GroupedLight]) {
        guard let index = groupedLights.firstIndex(where: { $0.id == event.id }) else { return }
        let existing = groupedLights[index]
        groupedLights[index] = GroupedLight(
            id: existing.id,
            on: event.on ?? existing.on,
            dimming: event.dimming ?? existing.dimming,
            colorTemperature: existing.colorTemperature
        )
    }

    static func apply(_ event: HueEventResource, to lights: inout [HueLight]) {
        guard let index = lights.firstIndex(where: { $0.id == event.id }) else { return }
        let existing = lights[index]
        lights[index] = HueLight(
            id: existing.id,
            owner: existing.owner,
            metadata: existing.metadata,
            on: event.on ?? existing.on,
            dimming: event.dimming ?? existing.dimming,
            color: event.color.map { LightColor(xy: $0.xy) } ?? existing.color,
            colorTemperature: event.colorTemperature.map { LightColorTemperature(mirek: $0.mirek, mirekValid: $0.mirekValid) } ?? existing.colorTemperature
        )
    }
}
