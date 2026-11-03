import Foundation

enum EventStreamUpdater {
    static func apply(_ event: HueEventResource, to groupedLights: inout [GroupedLight]) {
        guard let index = groupedLights.firstIndex(where: { $0.id == event.id }) else { return }
        if let on = event.on {
            groupedLights[index].on = on
        }
        if let dimming = event.dimming {
            groupedLights[index].dimming = dimming
        }
        if let colorTemperature = event.colorTemperature {
            groupedLights[index].colorTemperature = LightColorTemperature(
                mirek: colorTemperature.mirek,
                mirekValid: colorTemperature.mirekValid
            )
        }
    }

    static func apply(_ event: HueEventResource, to lights: inout [HueLight]) {
        guard let index = lights.firstIndex(where: { $0.id == event.id }) else { return }
        if let on = event.on {
            lights[index].on = on
        }
        if let dimming = event.dimming {
            lights[index].dimming = dimming
        }
        if let color = event.color {
            lights[index].color = LightColor(xy: color.xy)
        }
        if let colorTemperature = event.colorTemperature {
            lights[index].colorTemperature = LightColorTemperature(
                mirek: colorTemperature.mirek,
                mirekValid: colorTemperature.mirekValid
            )
        }
    }
}
