import SwiftUI

struct LightRowView: View {
    @Bindable var apiClient: HueAPIClient
    let name: String
    let archetype: String?
    let groupedLightId: String?
    let groupId: String
    var isPinned: Bool = false
    let onTap: () -> Void

    @State private var sliderBrightness: Double = 0
    @State private var debounceTask: Task<Void, Never>?

    private var groupedLight: GroupedLight? {
        apiClient.groupedLight(for: groupedLightId)
    }

    private var isOn: Bool {
        groupedLight?.isOn ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Icon + Name + Toggle row
            HStack(spacing: 8) {
                Button(action: onTap) {
                    HStack(spacing: 8) {
                        Image(systemName: ArchetypeIcon.systemName(for: archetype))
                            .font(.title2)
                            .foregroundStyle(isOn ? .white : .secondary)
                            .frame(width: 28)

                        Text(name)
                            .fontWeight(.medium)
                            .foregroundStyle(isOn ? .white : .primary)
                            .shadow(color: isOn ? .black.opacity(0.3) : .clear, radius: 2, y: 1)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(isOn ? .white.opacity(0.6) : .secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.6)) : AnyShapeStyle(.tertiary))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle("", isOn: toggleBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(groupedLightId == nil)
            }

            // Brightness slider (always visible for consistent card height)
            HStack(spacing: 4) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundStyle(isOn ? .white.opacity(0.6) : .white.opacity(0.2))
                Slider(value: $sliderBrightness, in: 1...100)
                    .controlSize(.small)
                    .tint(isOn ? .white.opacity(0.8) : .white.opacity(0.15))
                    .disabled(!isOn)
                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                    .foregroundStyle(isOn ? .white.opacity(0.6) : .white.opacity(0.2))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardGradient)
        )
        .padding(.horizontal)
        .onAppear {
            sliderBrightness = max(groupedLight?.brightness ?? 0, 1)
        }
        .onChange(of: groupedLight?.brightness) { _, newValue in
            if let newValue {
                sliderBrightness = max(newValue, 1)
            }
        }
        .onChange(of: sliderBrightness) { _, newValue in
            guard let id = groupedLightId else { return }
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                try? await apiClient.setBrightness(groupedLightId: id, brightness: newValue)
            }
        }
    }

    private var cardGradient: some ShapeStyle {
        guard isOn else {
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
        let colors = apiClient.activeSceneColors(for: groupId)
        if colors.count >= 2 {
            return AnyShapeStyle(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        } else if let first = colors.first {
            return AnyShapeStyle(
                LinearGradient(colors: [first, first.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        } else {
            return AnyShapeStyle(Color.white.opacity(0.15))
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                guard let id = groupedLightId else { return }
                Task { try? await apiClient.toggleGroupedLight(id: id, on: newValue) }
            }
        )
    }
}
