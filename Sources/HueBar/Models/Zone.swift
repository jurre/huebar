import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct Zone: LightGroup {
    let id: String
    let metadata: GroupMetadata
    let services: [ResourceLink]
    let children: [ResourceLink]
    
    var name: String { metadata.name }
    
    var groupedLightId: String? {
        services.first(where: { $0.rtype == "grouped_light" })?.rid
    }
}

// MARK: - Transferable

extension Zone: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .hueZone)
    }
}

extension UTType {
    static let hueZone = UTType(exportedAs: "com.huebar.zone")
}
