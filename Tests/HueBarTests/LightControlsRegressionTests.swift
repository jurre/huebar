import Testing
@testable import HueBar

@Suite("Light controls regressions")
struct LightControlsRegressionTests {
    @Test func bridgeBrightnessSyncsSliderWhenIdle() {
        let interaction = BrightnessSliderInteraction()

        #expect(interaction.bridgeBrightnessChanged(42) == .updateSlider(42))
        #expect(interaction.bridgeBrightnessChanged(0) == .updateSlider(1))
    }

    @Test func bridgeBrightnessDoesNotOverwriteSliderWhileDragging() {
        var interaction = BrightnessSliderInteraction()

        #expect(interaction.editingChanged(true, currentBrightness: 50) == .none)
        #expect(interaction.bridgeBrightnessChanged(12) == .none)
    }

    @Test func sliderChangesOnlyCommitWhileDragging() {
        var interaction = BrightnessSliderInteraction()

        #expect(interaction.sliderBrightnessChanged(55) == .none)
        #expect(interaction.editingChanged(true, currentBrightness: 55) == .none)
        #expect(interaction.sliderBrightnessChanged(60) == .commit(60))
    }

    @Test func endingDragCommitsCurrentSliderValue() {
        var interaction = BrightnessSliderInteraction()

        #expect(interaction.editingChanged(true, currentBrightness: 40) == .none)
        #expect(interaction.editingChanged(false, currentBrightness: 64) == .commitImmediately(64))
    }

    @Test(arguments: [
        (1.0, 0.0), (100.0, 1.0), (50.5, 0.5), (-20.0, 0.0), (250.0, 1.0),
    ])
    func brightnessSliderFillTracksValue(value: Double, expected: Double) {
        #expect(BrightnessSlider.fraction(for: value, in: 1...100) == expected)
    }

    @Test(arguments: [
        (9.0, 1.0), (109.0, 100.0), (59.0, 50.5), (0.0, 1.0), (-30.0, 1.0), (118.0, 100.0), (500.0, 100.0),
    ])
    func brightnessSliderDragMapsAcrossThumbTravel(x: Double, expected: Double) {
        // 118pt track with an 18pt thumb: the thumb centre travels from 9 to 109.
        #expect(BrightnessSlider.value(atX: x, width: 118, thumbSize: 18, in: 1...100) == expected)
    }

    @Test(arguments: [0.0, 10.0, 18.0])
    func brightnessSliderDragOnCollapsedTrackStaysAtMinimum(width: Double) {
        #expect(BrightnessSlider.value(atX: 5, width: width, thumbSize: 18, in: 1...100) == 1)
    }
}
