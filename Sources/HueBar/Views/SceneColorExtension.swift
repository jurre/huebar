import SwiftUI

extension ScenePaletteEntry {
    /// Full-color card swatch, independent of the bulb's dimming level.
    var vividColor: Color {
        switch self {
        case .xy(let xy, _):
            return xy.displayColor()
        case .colorTemperature(let mirek, _):
            return CIEXYColor.colorFromMirek(mirek)
        }
    }

    /// Convert a raw palette entry to a SwiftUI Color.
    var color: Color {
        switch self {
        case .xy(let xy, let brightness):
            return xy.swiftUIColor(brightness: brightness)
        case .colorTemperature(let mirek, let brightness):
            return CIEXYColor.colorFromMirek(mirek, brightness: brightness)
        }
    }
}

extension HueScene {
    /// SwiftUI colors derived from the scene's palette entries.
    var paletteColors: [Color] {
        paletteEntries.map(\.vividColor)
    }
}

extension HueAPIClient {
    /// Room cards show undimmed source colors; the slider communicates bulb brightness.
    func previewColors(for groupId: String?) -> [Color] {
        previewPaletteEntries(for: groupId).map(\.vividColor)
    }
}
