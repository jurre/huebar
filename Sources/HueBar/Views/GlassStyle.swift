import SwiftUI

// Liquid Glass adoption (macOS 26+).
//
// Every helper here falls back to the pre-Tahoe look on macOS 15, and the
// glass branches are wrapped in `#if compiler(>=6.2)` so the package still
// builds with Xcode 16 (the Liquid Glass APIs only exist in the macOS 26 SDK).

extension View {
    /// Card surface. On macOS 26 the fill is laid translucently over a Liquid
    /// Glass shape; `nil` means a plain (untinted) glass card. On earlier
    /// systems the fill is drawn opaque with a drop shadow, and `nil` falls
    /// back to `Color.hueCardOff`.
    @ViewBuilder
    func hueCard(
        fill: AnyShapeStyle?,
        cornerRadius: CGFloat,
        interactive: Bool = false,
        clip: Bool = false,
        shadowOpacity: Double = 0.25,
        shadowRadius: CGFloat = 4
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let filled = self.background {
                if let fill {
                    shape.fill(fill).opacity(0.75)
                }
            }
            let glass = Glass.regular.interactive(interactive)
            if clip {
                filled.clipShape(shape).glassEffect(glass, in: shape)
            } else {
                filled.glassEffect(glass, in: shape)
            }
        } else {
            legacyCard(fill: fill, shape: shape, clip: clip, shadowOpacity: shadowOpacity, shadowRadius: shadowRadius)
        }
        #else
        legacyCard(fill: fill, shape: shape, clip: clip, shadowOpacity: shadowOpacity, shadowRadius: shadowRadius)
        #endif
    }

    @ViewBuilder
    private func legacyCard(
        fill: AnyShapeStyle?,
        shape: RoundedRectangle,
        clip: Bool,
        shadowOpacity: Double,
        shadowRadius: CGFloat
    ) -> some View {
        let base = self.background(
            shape
                .fill(fill ?? AnyShapeStyle(Color.hueCardOff))
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowRadius / 2)
        )
        if clip {
            base.clipShape(shape)
        } else {
            base
        }
    }

    /// Small grouped surface for settings rows and chips (glass on macOS 26,
    /// a faint fill otherwise).
    @ViewBuilder
    func hueGroupedBackground(cornerRadius: CGFloat = 6, legacyOpacity: Double = 0.5) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.quaternary.opacity(legacyOpacity), in: shape)
        }
        #else
        self.background(.quaternary.opacity(legacyOpacity), in: shape)
        #endif
    }

    /// Lets neighbouring glass shapes blend and share a sampling region.
    @ViewBuilder
    func hueGlassContainer(spacing: CGFloat? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Glass button on macOS 26, `fallback` style otherwise.
    @ViewBuilder
    func hueGlassButtonStyle<S: PrimitiveButtonStyle>(fallback: S) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(fallback)
        }
        #else
        self.buttonStyle(fallback)
        #endif
    }

    /// Prominent (primary action) glass button on macOS 26, `.borderedProminent` otherwise.
    @ViewBuilder
    func hueProminentButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
        #else
        self.buttonStyle(.borderedProminent)
        #endif
    }

    /// Circular glass icon button (toolbar-style) on macOS 26, borderless otherwise.
    @ViewBuilder
    func hueGlassIconButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            self.buttonStyle(.borderless)
        }
        #else
        self.buttonStyle(.borderless)
        #endif
    }

    /// Soft scroll-edge fade under the header on macOS 26 (replaces the hard divider).
    @ViewBuilder
    func hueScrollEdge() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Header divider: hidden on macOS 26, where the scroll edge effect takes its place.
struct HeaderDivider: View {
    var body: some View {
        if isLiquidGlassAvailable {
            EmptyView()
        } else {
            Divider()
        }
    }
}

/// Glass thumb for custom slider controls.
struct GlassThumb: View {
    let size: CGFloat

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            legacy
        }
        #else
        legacy
        #endif
    }

    private var legacy: some View {
        Circle()
            .fill(.white)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .frame(width: size, height: size)
    }
}

/// Back button + title used by pushed screens. On macOS 26 the chevron sits in
/// its own glass circle next to the title, matching system navigation chrome.
struct BackHeaderButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        if isLiquidGlassAvailable {
            HStack(spacing: 8) {
                Button(action: action) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .hueGlassIconButtonStyle()
                .accessibilityLabel("Back")

                Text(title)
                    .font(.headline)
                    .lineLimit(1)
            }
        } else {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                    Text(title)
                        .font(.headline)
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

/// True when the Liquid Glass APIs are both compiled in and available at runtime.
var isLiquidGlassAvailable: Bool {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) { return true }
    #endif
    return false
}
