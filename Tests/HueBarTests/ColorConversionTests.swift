import Testing
import SwiftUI
@testable import HueBar

@Suite("Color Conversion Tests")
struct ColorConversionTests {

    // MARK: - swiftUIColor() should produce vibrant, not muddy colors

    @Test("swiftUIColor produces saturation above 0.6 for vivid input")
    func swiftUIColorSaturationNotCapped() {
        // Pure red-ish Hue light (x=0.675, y=0.322)
        let red = CIEXYColor(x: 0.675, y: 0.322)
        let color = red.swiftUIColor()

        // Extract HSB from the resulting color
        let hsb = extractHSB(from: color)
        // Saturation should not be capped at 0.65 anymore
        #expect(hsb.saturation > 0.6, "Saturation should be vibrant, got \(hsb.saturation)")
        // Brightness should be above 0.55 (old value was locked at 0.55)
        #expect(hsb.brightness > 0.6, "Brightness should be above 0.6, got \(hsb.brightness)")
    }

    @Test("swiftUIColor preserves distinct hues (no aggressive warm-shifting)")
    func swiftUIColorPreservesHues() {
        // Blue-ish light
        let blue = CIEXYColor(x: 0.167, y: 0.04)
        let blueHSB = extractHSB(from: blue.swiftUIColor())

        // Green-ish light
        let green = CIEXYColor(x: 0.17, y: 0.7)
        let greenHSB = extractHSB(from: green.swiftUIColor())

        // Red/orange light
        let red = CIEXYColor(x: 0.675, y: 0.322)
        let redHSB = extractHSB(from: red.swiftUIColor())

        // All three should have distinctly different hues — not all pulled toward orange
        let blueGreenDiff = abs(blueHSB.hue - greenHSB.hue)
        let blueRedDiff = abs(blueHSB.hue - redHSB.hue)
        #expect(blueGreenDiff > 0.1, "Blue and green should have different hues")
        #expect(blueRedDiff > 0.1, "Blue and red should have different hues")
    }

    // MARK: - colorFromMirek should not over-blend toward white

    @Test("colorFromMirek warm temperature not washed out")
    func colorFromMirekNotWashedOut() {
        // Very warm (2000K = 500 mirek)
        let warm = CIEXYColor.colorFromMirek(500)
        let hsb = extractHSB(from: warm)
        // Saturation should be meaningful, not washed out by excessive white blend
        #expect(hsb.saturation > 0.1, "Warm mirek color should have visible saturation, got \(hsb.saturation)")
    }

    @Test("colorFromMirek cool temperature stays bluish")
    func colorFromMirekCoolStaysBluish() {
        // Cool daylight (6500K = 153 mirek)
        let cool = CIEXYColor.colorFromMirek(153)
        let hsb = extractHSB(from: cool)
        // Should still be near white/blue, brightness should be high
        #expect(hsb.brightness > 0.8, "Cool mirek should be bright")
    }

    // MARK: - Helpers

    private func extractHSB(from color: Color) -> (hue: Double, saturation: Double, brightness: Double) {
        let resolved = color.resolve(in: .init())
        let r = Double(resolved.red)
        let g = Double(resolved.green)
        let b = Double(resolved.blue)

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var hue = 0.0
        if delta > 0 {
            if maxC == r {
                hue = (g - b) / delta
                if hue < 0 { hue += 6 }
            } else if maxC == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
        }
        let sat = maxC > 0 ? delta / maxC : 0
        return (hue: hue, saturation: sat, brightness: maxC)
    }
}
