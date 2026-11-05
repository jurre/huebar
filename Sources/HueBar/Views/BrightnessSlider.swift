import SwiftUI

/// Brightness slider for colored room cards. The native `Slider` doesn't honour
/// `.tint` over the card palette (on macOS 26 the remaining track renders bright
/// white and reads as the active side), so the fill and track are drawn here
/// from the card's foreground color.
struct BrightnessSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 1...100
    let color: Color
    let onEditingChanged: (Bool) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false

    private let thumbSize: CGFloat = 14
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbCenter = thumbSize / 2
                + CGFloat(Self.fraction(for: value, in: range)) * max(width - thumbSize, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isEnabled ? color.opacity(0.25) : Color.primary.opacity(0.1))
                    .frame(height: trackHeight)

                if isEnabled {
                    Capsule()
                        .fill(color.opacity(0.9))
                        .frame(width: thumbCenter, height: trackHeight)
                }

                GlassThumb(size: thumbSize)
                    .opacity(isEnabled ? 1 : 0.5)
                    .offset(x: thumbCenter - thumbSize / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        value = Self.value(atX: drag.location.x, width: width, thumbSize: thumbSize, in: range)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .allowsHitTesting(isEnabled)
        }
        .frame(height: thumbSize)
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        // Callers commit when an edit ends, so each VoiceOver step is a complete edit.
                        onEditingChanged(true)
                        value = newValue
                        onEditingChanged(false)
                    }
                ),
                in: range
            )
        }
    }

    nonisolated static func fraction(for value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// Maps a drag location to a value, matching the thumb centre's travel so the
    /// thumb stays under the pointer.
    nonisolated static func value(atX x: CGFloat, width: CGFloat, thumbSize: CGFloat, in range: ClosedRange<Double>) -> Double {
        let travel = width - thumbSize
        guard travel > 0 else { return range.lowerBound }
        let fraction = min(max((x - thumbSize / 2) / travel, 0), 1)
        return range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
    }
}
