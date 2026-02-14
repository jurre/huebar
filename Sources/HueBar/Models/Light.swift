import Foundation
import SwiftUI

struct HueLight: Decodable, Sendable, Identifiable {
    let id: String
    let owner: ResourceLink
    let metadata: LightMetadata
    let on: OnState
    let dimming: DimmingState?
    let color: LightColor?
    let colorTemperature: LightColorTemperature?

    enum CodingKeys: String, CodingKey {
        case id, owner, metadata, on, dimming, color
        case colorTemperature = "color_temperature"
    }

    var name: String { metadata.name }
    var isOn: Bool { on.on }
    var brightness: Double { dimming?.brightness ?? 0.0 }

    /// Vivid color for display indicators (colored dots)
    var displayColor: Color {
        if let xy = color?.xy {
            return xy.displayColor()
        }
        if let mirek = colorTemperature?.mirek {
            return CIEXYColor.colorFromMirek(mirek)
        }
        return CIEXYColor.colorFromMirek(370)
    }

    /// Current color as a SwiftUI Color for card backgrounds
    var currentColor: Color {
        if let xy = color?.xy {
            return xy.swiftUIColor()
        }
        if let mirek = colorTemperature?.mirek {
            return CIEXYColor.colorFromMirek(mirek)
        }
        // White-only light fallback
        return CIEXYColor.colorFromMirek(370)
    }

    var supportsColor: Bool { color != nil }
    var supportsColorTemperature: Bool { colorTemperature != nil }
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
    let mirekValid: Bool?

    enum CodingKeys: String, CodingKey {
        case mirek
        case mirekValid = "mirek_valid"
    }
}
