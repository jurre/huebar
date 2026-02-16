import Foundation

struct Room: LightGroup {
    let id: String
    let metadata: GroupMetadata
    let services: [ResourceLink]
    let children: [ResourceLink]
    
    var name: String { metadata.name }
    
    /// Find the grouped_light service reference
    var groupedLightId: String? {
        services.first(where: { $0.rtype == "grouped_light" })?.rid
    }
}
