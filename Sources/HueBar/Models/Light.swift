import Foundation
import SwiftUI

struct HueLight: Decodable, Sendable, Identifiable {
    let id: String
    let owner: ResourceLink
    let metadata: LightMetadata
    let on: OnState
    let dimming: DimmingState?
    let color: LightColor?
    let color_temperature: LightColorTemperature?

    var name: String { metadata.name }
    var isOn: Bool { on.on }
    var brightness: Double { dimming?.brightness ?? 0.0 }

    /// Current color as a SwiftUI Color for card backgrounds
    var currentColor: Color {
        if let xy = color?.xy {
            return xy.swiftUIColor()
        }
        if let mirek = color_temperature?.mirek {
            return CIEXYColor.colorFromMirek(mirek, brightness: 80)
        }
        // White-only light fallback
        return CIEXYColor.colorFromMirek(370, brightness: 80)
    }
}

struct LightMetadata: Decodable, Sendable {
    let name: String
    let archetype: String?
}

struct LightColor: Decodable, Sendable {
    let xy: CIEXYColor
}

struct LightColorTemperature: Decodable, Sendable {
    let mirek: Int?
    let mirek_valid: Bool?
}
