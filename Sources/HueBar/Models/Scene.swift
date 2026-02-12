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
        if let temps = palette.color_temperature, !temps.isEmpty {
            return temps.compactMap { entry in
                guard let mirek = entry.color_temperature?.mirek else { return nil }
                return CIEXYColor.colorFromMirek(mirek, brightness: entry.dimming?.brightness ?? 80)
            }
        }

        return []
    }
}

struct HueSceneMetadata: Decodable, Sendable {
    let name: String
}

struct HueSceneStatus: Decodable, Sendable {
    let active: String?
}

struct HueScenePalette: Decodable, Sendable {
    let color: [HueScenePaletteColor]
    let dimming: [HueScenePaletteDimming]?
    let color_temperature: [HueScenePaletteColorTemp]?
}

struct HueScenePaletteColor: Decodable, Sendable {
    let color: HueColorValue
    let dimming: HueScenePaletteDimming?
}

struct HueColorValue: Decodable, Sendable {
    let xy: CIEXYColor
}

struct CIEXYColor: Decodable, Sendable {
    let x: Double
    let y: Double

    /// Convert CIE 1931 xy + brightness to sRGB SwiftUI Color.
    /// Produces warm, muted tones suitable for dark-mode card backgrounds.
    func swiftUIColor(brightness: Double? = nil) -> Color {
        // CIE XY to XYZ (Y = 1.0 for full-range hue extraction)
        let z = 1.0 - x - y
        let yVal = 1.0
        let xVal = (yVal / max(y, 0.0001)) * x
        let zVal = (yVal / max(y, 0.0001)) * z

        // XYZ to linear sRGB (D65)
        var r =  xVal * 3.2406 + yVal * -1.5372 + zVal * -0.4986
        var g = xVal * -0.9689 + yVal *  1.8758 + zVal *  0.0415
        var b =  xVal * 0.0557 + yVal * -0.2040 + zVal *  1.0570

        // Clamp negatives
        r = max(r, 0); g = max(g, 0); b = max(b, 0)

        // Gamma correction (sRGB)
        func gammaCorrect(_ c: Double) -> Double {
            c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        }
        r = gammaCorrect(r)
        g = gammaCorrect(g)
        b = gammaCorrect(b)

        // Normalize if any channel exceeds 1.0
        let maxC = max(r, g, b, 1.0)
        r /= maxC; g /= maxC; b /= maxC

        // Convert RGB → HSB for predictable saturation/brightness control
        let rgbMax = max(r, g, b)
        let rgbMin = min(r, g, b)
        let delta = rgbMax - rgbMin

        var hue = 0.0
        if delta > 0 {
            if rgbMax == r {
                hue = (g - b) / delta
                if hue < 0 { hue += 6 }
            } else if rgbMax == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
        }

        let sat = rgbMax > 0 ? delta / rgbMax : 0

        // Warm-shift: pull all hues toward orange (0.06) via shortest
        // path on the hue circle. Colors are used as overlays on a warm
        // brown base, so they can be slightly more vivid.
        let warmTarget = 0.06
        var hueDiff = warmTarget - hue
        if hueDiff > 0.5 { hueDiff -= 1.0 }
        if hueDiff < -0.5 { hueDiff += 1.0 }
        var warmHue = hue + hueDiff * 0.15
        if warmHue < 0 { warmHue += 1 }
        if warmHue > 1 { warmHue -= 1 }

        return Color(hue: warmHue, saturation: min(sat, 0.65), brightness: 0.55)
    }

    /// Convert mirek color temperature to an approximate color.
    /// Mirek range: 153 (cool/blue, 6500K) to 500 (warm/orange, 2000K).
    static func colorFromMirek(_ mirek: Int, brightness: Double) -> Color {
        let kelvin = 1_000_000.0 / Double(max(mirek, 153))
        let temp = kelvin / 100.0

        var r: Double, g: Double, b: Double

        // Red
        if temp <= 66 {
            r = 1.0
        } else {
            r = 1.292936 * pow(temp - 60, -0.1332047592)
        }

        // Green
        if temp <= 66 {
            g = 0.3900815 * log(temp) - 0.6318414
        } else {
            g = 1.129891 * pow(temp - 60, -0.0755148492)
        }

        // Blue
        if temp >= 66 {
            b = 1.0
        } else if temp <= 19 {
            b = 0.0
        } else {
            b = 0.5432068 * log(temp - 10) - 1.19625408
        }

        r = min(max(r, 0), 1)
        g = min(max(g, 0), 1)
        b = min(max(b, 0), 1)

        // Blend toward white for a softer pastel look (40% white mix for temperatures)
        let mix = 0.4
        r = r + (1.0 - r) * mix
        g = g + (1.0 - g) * mix
        b = b + (1.0 - b) * mix

        return Color(red: r, green: g, blue: b)
    }
}

struct HueScenePaletteDimming: Decodable, Sendable {
    let brightness: Double
}

struct HueScenePaletteColorTemp: Decodable, Sendable {
    let color_temperature: HueColorTemperature?
    let dimming: HueScenePaletteDimming?
}

struct HueColorTemperature: Decodable, Sendable {
    let mirek: Int?
}
