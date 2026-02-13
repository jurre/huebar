import SwiftUI
import AppKit

struct SceneCard: View {
    let scene: HueScene
    let isActive: Bool
    var imageData: Data? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let nsImage = sceneImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .padding(.top, 4)
                }
                Spacer()
                Text(scene.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(sceneGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var sceneImage: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
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
