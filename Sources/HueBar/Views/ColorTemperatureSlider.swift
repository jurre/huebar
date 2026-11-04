import SwiftUI

struct ColorTemperatureSlider: View {
    @Binding var mirek: Int
    let onChanged: (Int) -> Void

    private let mirekRange = 153...500

    private let thumbSize: CGFloat = 20
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {
                // Gradient track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(
                        LinearGradient(
                            colors: Self.temperatureGradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)

                // Thumb
                GlassThumb(size: thumbSize)
                    .offset(x: thumbOffset(width: width, thumbSize: thumbSize))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, value.location.x / width))
                        // Left = warm (500), Right = cool (153) — reversed so warm is left
                        let newMirek = Int(Double(mirekRange.upperBound) - fraction * Double(mirekRange.upperBound - mirekRange.lowerBound))
                        let clamped = min(max(newMirek, mirekRange.lowerBound), mirekRange.upperBound)
                        mirek = clamped
                        onChanged(clamped)
                    }
            )
        }
        .frame(height: thumbSize)
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { Double(mirek) },
                    set: { value in
                        let newMirek = min(max(Int(value), mirekRange.lowerBound), mirekRange.upperBound)
                        mirek = newMirek
                        onChanged(newMirek)
                    }
                ),
                in: Double(mirekRange.lowerBound)...Double(mirekRange.upperBound),
                step: 1
            )
            .accessibilityLabel("Color temperature")
            .accessibilityValue("\(Int(1_000_000.0 / Double(max(mirek, 1)))) kelvin")
            .accessibilityHint("Increase for warmer light, decrease for cooler light")
        }
    }

    private func thumbOffset(width: CGFloat, thumbSize: CGFloat) -> CGFloat {
        // Warm (500) on the left, cool (153) on the right
        let fraction = Double(mirekRange.upperBound - mirek) / Double(mirekRange.upperBound - mirekRange.lowerBound)
        let usableWidth = width - thumbSize
        return CGFloat(fraction) * usableWidth
    }

    private static let temperatureGradientColors: [Color] =
        stride(from: 500, through: 153, by: -50).map { mirekVal in
            CIEXYColor.colorFromMirek(mirekVal)
        }
}
