import SwiftUI

struct LightCard: View {
    @Bindable var apiClient: HueAPIClient
    let light: HueLight
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: ArchetypeIcon.systemName(for: light.metadata.archetype))
                        .font(.title2)
                        .foregroundStyle(light.isOn ? .white : .secondary)

                    Spacer()

                    // Color indicator
                    Circle()
                        .fill(light.isOn ? light.displayColor : Color.gray.opacity(0.3))
                        .frame(width: 14, height: 14)

                    Toggle("", isOn: toggleBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                }

                Text(light.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(light.isOn ? .white : .primary)
                    .lineLimit(2)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some ShapeStyle {
        guard light.isOn else {
            return AnyShapeStyle(Color(red: 0.28, green: 0.24, blue: 0.22))
        }
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
