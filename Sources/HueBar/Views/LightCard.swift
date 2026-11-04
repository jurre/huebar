import SwiftUI

struct LightCard: View {
    @Bindable var apiClient: HueAPIClient
    let light: HueLight
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { onTap?() }) {
                HStack(spacing: 0) {
                    // Color accent strip
                    Rectangle()
                        .fill(light.isOn ? light.displayColor : Color.gray.opacity(0.3))
                        .frame(width: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: ArchetypeIcon.systemName(for: light.metadata.archetype))
                                .font(.title2)
                                .foregroundStyle(light.isOn ? .white : .secondary)

                            Spacer()

                            Color.clear.frame(width: 26, height: 16)
                        }

                        Text(light.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(light.isOn ? .white : .primary)
                            .lineLimit(2)
                    }
                    .padding(10)
                }
                .hueCard(fill: cardBackground, cornerRadius: 12, interactive: true, clip: true)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(light.name) details")

            Toggle("", isOn: toggleBinding)
                .toggleStyle(.switch)
                .tint(.hueAccent)
                .labelsHidden()
                .accessibilityLabel("Toggle \(light.name)")
                .controlSize(.mini)
                .padding(10)
        }
    }

    /// `nil` when off: plain glass on macOS 26, `hueCardOff` otherwise.
    private var cardBackground: AnyShapeStyle? {
        guard light.isOn else { return nil }
        let base = light.currentColor
        return AnyShapeStyle(
            LinearGradient(
                colors: [base.opacity(0.85), base.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { light.isOn },
            set: { newValue in
                Task { try? await apiClient.toggleLight(id: light.id, on: newValue) }
            }
        )
    }
}
