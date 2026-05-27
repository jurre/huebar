enum BrightnessSliderAction: Equatable {
    case none
    case updateSlider(Double)
    case commit(Double)
    case commitImmediately(Double)
}

struct BrightnessSliderInteraction {
    private(set) var isEditing = false

    mutating func editingChanged(_ editing: Bool, currentBrightness: Double) -> BrightnessSliderAction {
        isEditing = editing
        return editing ? .none : .commitImmediately(currentBrightness)
    }

    func bridgeBrightnessChanged(_ brightness: Double) -> BrightnessSliderAction {
        guard !isEditing else { return .none }
        return .updateSlider(Self.sliderValue(for: brightness))
    }

    func sliderBrightnessChanged(_ brightness: Double) -> BrightnessSliderAction {
        guard isEditing else { return .none }
        return .commit(brightness)
    }

    static func sliderValue(for brightness: Double) -> Double {
        max(brightness, 1)
    }
}
