import SwiftUI

struct ColorTemperatureSlider: View {
    @Binding var mirek: Int
    let onChanged: (Int) -> Void

    private let mirekRange = 153...500

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let thumbSize: CGFloat = 24
            let trackHeight: CGFloat = 24

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
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbOffset(width: width, thumbSize: thumbSize))
            }
            .frame(height: height)
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
        .frame(height: 28)
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
