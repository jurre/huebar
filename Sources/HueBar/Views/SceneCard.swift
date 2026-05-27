import AppKit
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
            ZStack(alignment: .bottom) {
                SceneArtworkBackground(scene: scene)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(scene.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    .padding(6)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? Color.white : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
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
                .background(.black.opacity(0.35), in: Circle())
        }
        .accessibilityLabel(isDynamic ? "Pause dynamic scene" : "Play dynamic scene")
        .buttonStyle(.plain)
    }
}

private struct SceneArtworkBackground: View {
    let scene: HueScene

    private var artwork: SceneArtworkDescriptor {
        scene.artwork
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let imageName = artwork.imageName,
                   let image = SceneArtworkImageLoader.image(named: imageName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
        }
    }

    private var backgroundColors: [Color] {
        let colors = scene.paletteColors
        if colors.count >= 2 {
            return colors
        } else if let first = colors.first {
            return [first, first.opacity(0.6)]
        } else {
            return [
                .orange.opacity(0.6),
                .purple.opacity(0.5),
            ]
        }
    }
}

@MainActor
private enum SceneArtworkImageLoader {
    static func image(named name: String) -> NSImage? {
        if let url = SceneArtworkCatalog.url(forImageNamed: name) {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}
