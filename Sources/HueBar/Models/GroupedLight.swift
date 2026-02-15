import Foundation

struct GroupedLight: Decodable, Sendable, Identifiable {
    let id: String
    var on: OnState?
    var dimming: DimmingState?
    var colorTemperature: LightColorTemperature?

    var isOn: Bool { on?.on ?? false }
    var brightness: Double { dimming?.brightness ?? 0.0 }
    var mirek: Int? { colorTemperature?.mirek }

    enum CodingKeys: String, CodingKey {
        case id, on, dimming
        case colorTemperature = "color_temperature"
    }
}


