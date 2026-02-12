import Foundation

struct HueResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let errors: [HueError]
    let data: [T]
}

struct HueError: Decodable, Sendable {
    let description: String
}

struct ResourceLink: Decodable, Sendable, Hashable {
    let rid: String
    let rtype: String
}

struct Room: Decodable, Sendable, Identifiable {
    let id: String
    let metadata: RoomMetadata
    let services: [ResourceLink]
    let children: [ResourceLink]
    
    var name: String { metadata.name }
    
    /// Find the grouped_light service reference
    var groupedLightId: String? {
        services.first(where: { $0.rtype == "grouped_light" })?.rid
    }
}

struct RoomMetadata: Decodable, Sendable {
    let name: String
    let archetype: String?
}
