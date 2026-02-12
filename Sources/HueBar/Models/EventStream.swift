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
    let color_temperature: HueEventColorTemp?
    let status: HueSceneStatus?
    let metadata: HueEventMetadata?

    var resourceType: String { type }
}

struct HueEventColor: Decodable, Sendable {
    let xy: CIEXYColor
}

struct HueEventColorTemp: Decodable, Sendable {
    let mirek: Int?
    let mirek_valid: Bool?
}

struct HueEventMetadata: Decodable, Sendable {
    let name: String?
}
