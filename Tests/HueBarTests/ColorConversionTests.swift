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

    // MARK: - displayColor()

    @Test("displayColor returns a valid color for a known CIE point")
    func displayColorReturnsValidColor() {
        let red = CIEXYColor(x: 0.675, y: 0.322)
        let color = red.displayColor()
        let hsb = extractHSB(from: color)
        // Should be reddish (hue near 0 or 1) with high saturation
        #expect(hsb.brightness > 0.0, "displayColor should produce a visible color")
        #expect(hsb.saturation > 0.3, "displayColor for a saturated input should retain saturation, got \(hsb.saturation)")
        #expect(hsb.hue < 0.1 || hsb.hue > 0.9, "Red CIE point should map to reddish hue, got \(hsb.hue)")
    }

    @Test("displayColor for green CIE point is greenish")
    func displayColorGreenPoint() {
        let green = CIEXYColor(x: 0.17, y: 0.7)
        let color = green.displayColor()
        let hsb = extractHSB(from: color)
        // Green hue is around 0.33
        #expect(hsb.hue > 0.2 && hsb.hue < 0.5, "Green CIE point should map to greenish hue, got \(hsb.hue)")
    }

    // MARK: - fromHSB(hue:saturation:)

    @Test("fromHSB pure red maps to expected CIE xy")
    func fromHSBPureRed() {
        let cie = CIEXYColor.fromHSB(hue: 0.0, saturation: 1.0)
        #expect(abs(cie.x - 0.64) < 0.05, "Red x should be ~0.64, got \(cie.x)")
        #expect(abs(cie.y - 0.33) < 0.05, "Red y should be ~0.33, got \(cie.y)")
    }

    @Test("fromHSB pure green maps to expected CIE xy")
    func fromHSBPureGreen() {
        let cie = CIEXYColor.fromHSB(hue: 1.0 / 3.0, saturation: 1.0)
        #expect(abs(cie.x - 0.30) < 0.05, "Green x should be ~0.30, got \(cie.x)")
        #expect(abs(cie.y - 0.60) < 0.05, "Green y should be ~0.60, got \(cie.y)")
    }

    @Test("fromHSB pure blue maps to expected CIE xy")
    func fromHSBPureBlue() {
        let cie = CIEXYColor.fromHSB(hue: 2.0 / 3.0, saturation: 1.0)
        #expect(abs(cie.x - 0.15) < 0.05, "Blue x should be ~0.15, got \(cie.x)")
        #expect(abs(cie.y - 0.06) < 0.05, "Blue y should be ~0.06, got \(cie.y)")
    }

    // MARK: - toHSB() round-trip

    @Test("fromHSB → toHSB round-trip preserves hue and saturation")
    func fromHSBToHSBRoundTrip() {
        let testCases: [(hue: Double, sat: Double)] = [
            (0.0, 1.0),    // red
            (0.33, 0.8),   // green-ish
            (0.66, 0.9),   // blue-ish
            (0.1, 0.5),    // orange-ish
        ]
        for tc in testCases {
            let cie = CIEXYColor.fromHSB(hue: tc.hue, saturation: tc.sat)
            let hsb = cie.toHSB()
            #expect(abs(hsb.hue - tc.hue) < 0.05, "Hue round-trip failed: input \(tc.hue), got \(hsb.hue)")
            #expect(abs(hsb.saturation - tc.sat) < 0.1, "Saturation round-trip failed: input \(tc.sat), got \(hsb.saturation)")
        }
    }

    // MARK: - colorFromMirek boundary values

    @Test("colorFromMirek 153 (coolest valid) produces bright color")
    func colorFromMirekCoolest() {
        let color = CIEXYColor.colorFromMirek(153)
        let hsb = extractHSB(from: color)
        #expect(hsb.brightness > 0.8, "Mirek 153 should be very bright, got \(hsb.brightness)")
    }

    @Test("colorFromMirek 500 (warmest) produces warm color")
    func colorFromMirekWarmest() {
        let color = CIEXYColor.colorFromMirek(500)
        let hsb = extractHSB(from: color)
        // Warm color: hue near red/orange (< 0.15)
        #expect(hsb.hue < 0.15 || hsb.hue > 0.9, "Mirek 500 should be warm/orange, got hue \(hsb.hue)")
        #expect(hsb.saturation > 0.05, "Mirek 500 should have some saturation, got \(hsb.saturation)")
    }

    @Test("colorFromMirek 0 handles gracefully without crash")
    func colorFromMirekZero() {
        // mirek=0 would cause division by zero without the max(mirek, 153) guard
        let color = CIEXYColor.colorFromMirek(0)
        let hsb = extractHSB(from: color)
        // Should not crash and should produce a valid color
        #expect(hsb.brightness > 0.0, "Mirek 0 should still produce a visible color")
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
