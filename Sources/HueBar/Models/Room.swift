import CoreTransferable
import Foundation
import UniformTypeIdentifiers

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

// MARK: - Transferable

extension Room: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .hueRoom)
    }
}

extension UTType {
    static let hueRoom = UTType(exportedAs: "com.huebar.room")
}
