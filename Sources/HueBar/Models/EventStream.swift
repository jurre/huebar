import Foundation

struct HueEvent: Decodable, Sendable {
    let creationtime: String
    let id: String
    let type: HueEventType
    let data: [HueEventResource]
}

enum HueEventType: String, Decodable, Sendable {
    case update
    case add
    case delete
}

struct HueEventResource: Decodable, Sendable {
    let id: String
    let type: String
    let on: OnState?
    let dimming: DimmingState?
    let color: HueEventColor?
    let colorTemperature: HueEventColorTemp?
    let status: HueSceneStatus?
    let metadata: HueEventMetadata?
    let speed: Double?

    enum CodingKeys: String, CodingKey {
        case id, type, on, dimming, color, status, metadata, speed
        case colorTemperature = "color_temperature"
    }
}

struct HueEventColor: Decodable, Sendable {
    let xy: CIEXYColor
}

struct HueEventColorTemp: Decodable, Sendable {
    let mirek: Int?
    let mirekValid: Bool?

    enum CodingKeys: String, CodingKey {
        case mirek
        case mirekValid = "mirek_valid"
    }
}

struct HueEventMetadata: Decodable, Sendable {
    let name: String?
}
