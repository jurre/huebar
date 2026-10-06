import SwiftUI

struct SceneCard: View {
    let scene: HueScene
    let isActive: Bool
    var isDynamic: Bool = false
    let onTap: () -> Void
    var onPlayPause: (() -> Void)?

    var body: some View {
        ZStack {
            cardContent
            if isActive && scene.supportsDynamic {
                playPauseButton
                    .offset(y: -8)
            }
        }
    }

    private var cardContent: some View {
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
            .hueCard(fill: sceneGradient, cornerRadius: 12, interactive: true)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(scene.name) scene\(isActive ? ", active" : "")")
    }

    private var playPauseButton: some View {
        Button {
            onPlayPause?()
        } label: {
            Image(systemName: isDynamic ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(isLiquidGlassAvailable ? .clear : .black.opacity(0.35), in: Circle())
        }
        .accessibilityLabel(isDynamic ? "Pause dynamic scene" : "Play dynamic scene")
        .hueGlassButtonStyle(fallback: .plain)
        .buttonBorderShape(.circle)
    }

    private var sceneGradient: AnyShapeStyle {
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
