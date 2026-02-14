import Foundation
import SwiftUI

struct HueScene: Decodable, Sendable, Identifiable {
    let id: String
    let metadata: HueSceneMetadata
    let group: ResourceLink
    let status: HueSceneStatus?
    let palette: HueScenePalette?

    var name: String { metadata.name }

    /// Extract SwiftUI colors from the scene's palette
    var paletteColors: [Color] {
        guard let palette else { return [] }

        // Use XY palette colors if available
        if !palette.color.isEmpty {
            return palette.color.map { entry in
                entry.color.xy.swiftUIColor(brightness: entry.dimming?.brightness)
            }
        }

        // Fall back to color temperature (warm/cool whites)
        if let temps = palette.colorTemperature, !temps.isEmpty {
            return temps.compactMap { entry in
                guard let mirek = entry.colorTemperature?.mirek else { return nil }
                return CIEXYColor.colorFromMirek(mirek)
            }
        }

        return []
    }
}

struct HueSceneMetadata: Decodable, Sendable {
    let name: String
    let image: ResourceLink?
}

enum HueSceneActiveState: String, Decodable, Sendable {
    case active
    case `static`
    case inactive
}

struct HueSceneStatus: Decodable, Sendable {
    let active: HueSceneActiveState?
}

struct HueScenePalette: Decodable, Sendable {
    let color: [HueScenePaletteColor]
    let dimming: [HueScenePaletteDimming]?
    let colorTemperature: [HueScenePaletteColorTemp]?

    enum CodingKeys: String, CodingKey {
        case color, dimming
        case colorTemperature = "color_temperature"
    }
}

struct HueScenePaletteColor: Decodable, Sendable {
    let color: HueColorValue
    let dimming: HueScenePaletteDimming?
}

struct HueColorValue: Decodable, Sendable {
    let xy: CIEXYColor
}

struct CIEXYColor: Codable, Sendable {
    let x: Double
    let y: Double
}

struct HueScenePaletteDimming: Decodable, Sendable {
    let brightness: Double
}

struct HueScenePaletteColorTemp: Decodable, Sendable {
    let colorTemperature: HueColorTemperature?
    let dimming: HueScenePaletteDimming?

    enum CodingKeys: String, CodingKey {
        case colorTemperature = "color_temperature"
        case dimming
    }
}

struct HueColorTemperature: Decodable, Sendable {
    let mirek: Int?
}
