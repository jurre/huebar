import SwiftUI

struct LightCard: View {
    @Bindable var apiClient: HueAPIClient
    let light: HueLight
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        let color = light.cardColor
        let foreground = ColorCardStyle.foreground(for: [color])

        ZStack(alignment: .topTrailing) {
            Button(action: { onTap?() }) {
                HStack(spacing: 0) {
                    // Color accent strip
                    Rectangle()
                        .fill(light.isOn ? color : Color.gray.opacity(0.3))
                        .frame(width: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: ArchetypeIcon.systemName(for: light.metadata.archetype))
                                .font(.title2)
                                .foregroundStyle(light.isOn ? foreground : .secondary)

                            Spacer()

                            Color.clear.frame(width: 26, height: 16)
                        }

                        Text(light.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(light.isOn ? foreground : .primary)
                            .lineLimit(2)
                    }
                    .padding(10)
                }
                .modifier(ColorCardStyle(
                    colors: light.isOn ? [color] : nil, cornerRadius: 12, clip: true
                ))
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

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { light.isOn },
            set: { newValue in
                Task { try? await apiClient.toggleLight(id: light.id, on: newValue) }
            }
        )
    }
}
