import Foundation

struct GroupedLight: Decodable, Sendable, Identifiable {
    let id: String
    let on: OnState?
    let dimming: DimmingState?
    let colorTemperature: LightColorTemperature?

    var isOn: Bool { on?.on ?? false }
    var brightness: Double { dimming?.brightness ?? 0.0 }
    var mirek: Int? { colorTemperature?.mirek }

    enum CodingKeys: String, CodingKey {
        case id, on, dimming
        case colorTemperature = "color_temperature"
    }
}


