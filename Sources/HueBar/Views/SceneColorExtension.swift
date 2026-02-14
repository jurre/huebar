import SwiftUI

extension ScenePaletteEntry {
    /// Convert a raw palette entry to a SwiftUI Color.
    var color: Color {
        switch self {
        case .xy(let xy, let brightness):
            return xy.swiftUIColor(brightness: brightness)
        case .colorTemperature(let mirek):
            return CIEXYColor.colorFromMirek(mirek)
        }
    }
}

extension HueScene {
    /// SwiftUI colors derived from the scene's palette entries.
    var paletteColors: [Color] {
        paletteEntries.map(\.color)
    }
}

extension HueAPIClient {
    /// Convenience for views: converts raw palette entries to SwiftUI Colors.
    func activeSceneColors(for groupId: String?) -> [Color] {
        activeScenePaletteEntries(for: groupId).map(\.color)
    }
}
