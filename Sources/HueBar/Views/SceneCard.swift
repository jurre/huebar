import SwiftUI

struct SceneCard: View {
    let scene: HueScene
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Spacer()
                Text(scene.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(sceneGradient)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var sceneGradient: some ShapeStyle {
        let colors = scene.paletteColors
        if colors.count >= 2 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else if let first = colors.first {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [first, first.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.orange.opacity(0.6), .purple.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}
