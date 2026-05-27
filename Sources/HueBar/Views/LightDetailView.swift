import SwiftUI

struct LightDetailView: View {
    @Bindable var apiClient: HueAPIClient
    let light: HueLight
    let onDone: () -> Void

    @State private var sliderBrightness: Double = 0
    @State private var colorXY: CIEXYColor = CIEXYColor(x: 0.3127, y: 0.3290)
    @State private var colorTempMirek: Int = 370
    @State private var brightnessDebounce: Task<Void, Never>?
    @State private var colorDebounce: Task<Void, Never>?
    @State private var tempDebounce: Task<Void, Never>?
    @State private var brightnessInteraction = BrightnessSliderInteraction()

    var body: some View {
        VStack(spacing: 12) {
            // Header with light name and Done button
            HStack {
                Text(light.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    onDone()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.medium))
            }

            // Color wheel for full-color lights
            if light.supportsColor {
                ColorWheelView(xy: $colorXY) { newXY in
                    apiClient.previewLightColor(id: light.id, xy: newXY)
                    debounce(task: &colorDebounce) {
                        try? await apiClient.setLightColor(id: light.id, xy: newXY)
                    }
                }
                .frame(height: 160)
            }

            // Color temperature slider for temp-only lights (not shown if full color is available)
            if !light.supportsColor && light.supportsColorTemperature {
                ColorTemperatureSlider(mirek: $colorTempMirek) { newMirek in
                    apiClient.previewLightColorTemperature(id: light.id, mirek: newMirek)
                    debounce(task: &tempDebounce) {
                        try? await apiClient.setLightColorTemperature(id: light.id, mirek: newMirek)
                    }
                }
            }

            // Brightness slider
            if light.dimming != nil {
                HStack(spacing: 6) {
                    Image(systemName: "sun.min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $sliderBrightness, in: 1...100) { editing in
                        handleBrightnessAction(
                            brightnessInteraction.editingChanged(editing, currentBrightness: sliderBrightness)
                        )
                    }
                        .controlSize(.small)
                        .tint(.hueAccent)
                        .accessibilityLabel("\(light.name) brightness")
                        .accessibilityValue("\(Int(sliderBrightness))%")
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { syncFromLight() }
        .onChange(of: light.id) { _, _ in syncFromLight() }
        .onChange(of: light.brightness) { _, newValue in
            handleBrightnessAction(brightnessInteraction.bridgeBrightnessChanged(newValue))
        }
        .onChange(of: sliderBrightness) { _, newValue in
            handleBrightnessAction(brightnessInteraction.sliderBrightnessChanged(newValue))
        }
        .onDisappear {
            brightnessDebounce?.cancel()
            colorDebounce?.cancel()
            tempDebounce?.cancel()
        }
    }

    private func syncFromLight() {
        sliderBrightness = BrightnessSliderInteraction.sliderValue(for: light.brightness)
        if let xy = light.color?.xy {
            colorXY = xy
        }
        if let mirek = light.colorTemperature?.mirek {
            colorTempMirek = mirek
        }
    }

    private func handleBrightnessAction(_ action: BrightnessSliderAction) {
        switch action {
        case .none:
            break
        case .updateSlider(let brightness):
            sliderBrightness = brightness
        case .commit(let brightness):
            commitBrightnessChange(brightness)
        case .commitImmediately(let brightness):
            commitBrightnessChange(brightness, immediately: true)
        }
    }

    private func commitBrightnessChange(_ brightness: Double, immediately: Bool = false) {
        apiClient.previewLightBrightness(id: light.id, brightness: brightness)
        if immediately {
            brightnessDebounce?.cancel()
            brightnessDebounce = Task {
                try? await apiClient.setLightBrightness(id: light.id, brightness: brightness)
            }
            return
        }

        debounce(task: &brightnessDebounce) {
            try? await apiClient.setLightBrightness(id: light.id, brightness: brightness)
        }
    }
}
