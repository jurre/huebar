import SwiftUI

struct ColorCardStyle: ViewModifier {
    let colors: [Color]?
    let cornerRadius: CGFloat
    var shadowOpacity: Double = 0.25
    var shadowRadius: CGFloat = 4
    var clip: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if let colors {
            let filled = content.background {
                // Opaque color keeps glass and the desktop from washing out the palette.
                LinearGradient(
                    colors: colors.isEmpty ? [Color(white: 0.45)] : colors,
                    startPoint: .leading, endPoint: .trailing
                )
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.58)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .clipShape(shape)
            }
            if clip {
                filled.clipShape(shape)
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowRadius / 2)
            } else {
                filled.shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowRadius / 2)
            }
        } else {
            content.hueCard(
                fill: nil, cornerRadius: cornerRadius, interactive: true, clip: clip,
                shadowOpacity: shadowOpacity, shadowRadius: shadowRadius
            )
        }
    }

    static func foreground(for colors: [Color]) -> Color {
        // Near-white palettes need dark content without dimming the colors themselves.
        let isPale = !colors.isEmpty && colors.allSatisfy { color in
            let rgb = color.resolve(in: .init())
            func linearize(_ component: Float) -> Double {
                let value = Double(component)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linearize(rgb.red)
                + 0.7152 * linearize(rgb.green)
                + 0.0722 * linearize(rgb.blue)
            return luminance > 0.8
        }
        return isPale ? .black : .white
    }
}
