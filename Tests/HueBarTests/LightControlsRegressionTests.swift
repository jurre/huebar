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
        #expect(interaction.editingChanged(false, currentBrightness: 64) == .commit(64))
    }
}
