import Foundation

struct Zone: Decodable, Sendable, Identifiable {
    let id: String
    let metadata: ZoneMetadata
    let services: [ResourceLink]
    let children: [ResourceLink]
    
    var name: String { metadata.name }
    
    var groupedLightId: String? {
        services.first(where: { $0.rtype == "grouped_light" })?.rid
    }
}

struct ZoneMetadata: Decodable, Sendable {
    let name: String
    let archetype: String?
}
