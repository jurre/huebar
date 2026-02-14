import Foundation
import SwiftUI

extension Color {
    /// The warm orange accent used for sliders and toggles.
    static let hueAccent = Color(red: 0.95, green: 0.65, blue: 0.25)
    static let hueCardOff = Color(red: 0.28, green: 0.24, blue: 0.22)
}

extension CIEXYColor {
    /// CIE xy → XYZ → linear sRGB → gamma-corrected sRGB, normalized to 0…1.
    private func toSRGB() -> (r: Double, g: Double, b: Double) {
        let z = 1.0 - x - y
        let yVal = 1.0
        let xVal = (yVal / max(y, 0.0001)) * x
        let zVal = (yVal / max(y, 0.0001)) * z

        var r =  xVal * 3.2406 + yVal * -1.5372 + zVal * -0.4986
        var g = xVal * -0.9689 + yVal *  1.8758 + zVal *  0.0415
        var b =  xVal * 0.0557 + yVal * -0.2040 + zVal *  1.0570
        r = max(r, 0); g = max(g, 0); b = max(b, 0)

        func gammaCorrect(_ c: Double) -> Double {
            c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        }
        r = gammaCorrect(r); g = gammaCorrect(g); b = gammaCorrect(b)

        let maxC = max(r, g, b, 1.0)
        return (r: r / maxC, g: g / maxC, b: b / maxC)
    }

    /// Vivid color for display indicators (colored dots, previews).
    func displayColor() -> Color {
        let rgb = toSRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Convert CIE 1931 xy + brightness to sRGB SwiftUI Color.
    /// Produces vibrant colors suitable for dark-mode card backgrounds.
    func swiftUIColor(brightness: Double? = nil) -> Color {
        let rgb = toSRGB()

        // Convert RGB → HSB for predictable saturation/brightness control
        let rgbMax = max(rgb.r, rgb.g, rgb.b)
        let rgbMin = min(rgb.r, rgb.g, rgb.b)
        let delta = rgbMax - rgbMin

        var hue = 0.0
        if delta > 0 {
            if rgbMax == rgb.r {
                hue = (rgb.g - rgb.b) / delta
                if hue < 0 { hue += 6 }
            } else if rgbMax == rgb.g {
                hue = (rgb.b - rgb.r) / delta + 2
            } else {
                hue = (rgb.r - rgb.g) / delta + 4
            }
            hue /= 6
        }

        let sat = rgbMax > 0 ? delta / rgbMax : 0

        // Gentle warm-shift: very subtle pull toward orange (0.06), only 5%
        let warmTarget = 0.06
        var hueDiff = warmTarget - hue
        if hueDiff > 0.5 { hueDiff -= 1.0 }
        if hueDiff < -0.5 { hueDiff += 1.0 }
        var warmHue = hue + hueDiff * 0.05
        if warmHue < 0 { warmHue += 1 }
        if warmHue > 1 { warmHue -= 1 }

        return Color(hue: warmHue, saturation: min(sat, 0.85), brightness: 0.70)
    }

    /// Convert mirek color temperature to an approximate color.
    /// Mirek range: 153 (cool/blue, 6500K) to 500 (warm/orange, 2000K).
    static func colorFromMirek(_ mirek: Int) -> Color {
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

        // Blend toward white for a softer look (20% white mix)
        let mix = 0.2
        r = r + (1.0 - r) * mix
        g = g + (1.0 - g) * mix
        b = b + (1.0 - b) * mix

        return Color(red: r, green: g, blue: b)
    }

    /// Convert HSB (hue/saturation/brightness all 0…1) to CIE xy.
    static func fromHSB(hue: Double, saturation: Double) -> CIEXYColor {
        // HSB → RGB
        let c = saturation
        let h6 = hue * 6.0
        let x2 = c * (1.0 - abs(h6.truncatingRemainder(dividingBy: 2.0) - 1.0))
        var r = 0.0, g = 0.0, b = 0.0
        switch Int(h6) % 6 {
        case 0: r = c; g = x2; b = 0
        case 1: r = x2; g = c; b = 0
        case 2: r = 0; g = c; b = x2
        case 3: r = 0; g = x2; b = c
        case 4: r = x2; g = 0; b = c
        default: r = c; g = 0; b = x2
        }
        let m = 1.0 - c
        r += m; g += m; b += m

        // Inverse gamma (sRGB)
        func linearize(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let lr = linearize(r), lg = linearize(g), lb = linearize(b)

        // RGB → CIE XYZ (D65)
        let bigX = lr * 0.4124 + lg * 0.3576 + lb * 0.1805
        let bigY = lr * 0.2126 + lg * 0.7152 + lb * 0.0722
        let bigZ = lr * 0.0193 + lg * 0.1192 + lb * 0.9505
        let sum = bigX + bigY + bigZ
        guard sum > 0 else { return CIEXYColor(x: 0.3127, y: 0.3290) } // D65 white
        return CIEXYColor(x: bigX / sum, y: bigY / sum)
    }

    /// Convert CIE xy back to HSB (hue & saturation in 0…1).
    func toHSB() -> (hue: Double, saturation: Double) {
        let rgb = toSRGB()

        // RGB → HSB
        let rgbMax = max(rgb.r, rgb.g, rgb.b)
        let rgbMin = min(rgb.r, rgb.g, rgb.b)
        let delta = rgbMax - rgbMin
        var hue = 0.0
        if delta > 0 {
            if rgbMax == rgb.r {
                hue = (rgb.g - rgb.b) / delta
                if hue < 0 { hue += 6 }
            } else if rgbMax == rgb.g {
                hue = (rgb.b - rgb.r) / delta + 2
            } else {
                hue = (rgb.r - rgb.g) / delta + 4
            }
            hue /= 6
        }
        let sat = rgbMax > 0 ? delta / rgbMax : 0
        return (hue: hue, saturation: sat)
    }
}
