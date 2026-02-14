import Foundation

/// Raw palette entry without SwiftUI dependency.
/// View-layer code converts these to `Color` via the extension in SceneColorExtension.swift.
enum ScenePaletteEntry: Sendable {
    case xy(CIEXYColor, brightness: Double?)
    case colorTemperature(mirek: Int)
}

struct HueScene: Decodable, Sendable, Identifiable {
    let id: String
    let type: String?
    let metadata: HueSceneMetadata
    let group: ResourceLink
    let status: HueSceneStatus?
    let palette: HueScenePalette?
    let speed: Double?
    let autoDynamic: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, metadata, group, status, palette, speed
        case autoDynamic = "auto_dynamic"
    }

    var name: String { metadata.name }

    /// Whether the scene is currently in dynamic palette mode
    var isDynamicActive: Bool {
        status?.active == .dynamicPalette
    }

    /// Whether this scene has any palette colors (used by the UI for gradient display)
    var hasPalette: Bool {
        !paletteEntries.isEmpty
    }

    /// Whether this scene supports dynamic palette mode
    var supportsDynamic: Bool {
        palette != nil || autoDynamic == true
    }

    /// Raw CIE palette entries for this scene (no SwiftUI dependency).
    var paletteEntries: [ScenePaletteEntry] {
        guard let palette else { return [] }

        // Use XY palette colors if available
        if !palette.color.isEmpty {
            return palette.color.map { entry in
                .xy(entry.color.xy, brightness: entry.dimming?.brightness)
            }
        }

        // Fall back to color temperature (warm/cool whites)
        if let temps = palette.colorTemperature, !temps.isEmpty {
            return temps.compactMap { entry in
                guard let mirek = entry.colorTemperature?.mirek else { return nil }
                return .colorTemperature(mirek: mirek)
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
    case dynamicPalette = "dynamic_palette"
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
