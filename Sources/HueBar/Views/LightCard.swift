import SwiftUI

struct LightCard: View {
    @Bindable var apiClient: HueAPIClient
    let light: HueLight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: ArchetypeIcon.systemName(for: light.metadata.archetype))
                    .font(.title2)
                    .foregroundStyle(light.isOn ? .white : .secondary)

                Spacer()

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
            RoundedRectangle(cornerRadius: 10)
                .fill(light.isOn ? AnyShapeStyle(light.currentColor.opacity(0.7)) : AnyShapeStyle(Color.gray.opacity(0.15)))
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
