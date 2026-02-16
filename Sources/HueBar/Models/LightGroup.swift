import Foundation

protocol LightGroup: Codable, Sendable, Identifiable where ID == String {
    var id: String { get }
    var name: String { get }
    var services: [ResourceLink] { get }
    var children: [ResourceLink] { get }
    var groupedLightId: String? { get }
}

struct GroupMetadata: Codable, Sendable {
    let name: String
    let archetype: String?
}
