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
    @State private var isUserDragging = false
    @State private var debounceTask: Task<Void, Never>?

    private var groupedLight: GroupedLight? {
        apiClient.groupedLight(for: groupedLightId)
    }

    private var isOn: Bool {
        groupedLight?.isOn ?? false
    }

    var body: some View {
        let colors = isOn ? apiClient.previewColors(for: groupId) : []
        let foreground = ColorCardStyle.foreground(for: colors)

        VStack(alignment: .leading, spacing: 6) {
            // Icon + Name + Toggle row
            HStack(spacing: 8) {
                Button(action: onTap) {
                    HStack(spacing: 8) {
                        Image(systemName: ArchetypeIcon.systemName(for: archetype))
                            .font(.title2)
                            .foregroundStyle(isOn ? foreground : .secondary)
                            .frame(width: 28)

                        Text(name)
                            .fontWeight(.medium)
                            .foregroundStyle(isOn ? foreground : .primary)
                            .shadow(color: isOn && foreground == .white ? .black.opacity(0.3) : .clear, radius: 2, y: 1)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(isOn ? foreground.opacity(0.6) : .secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(isOn ? AnyShapeStyle(foreground.opacity(0.6)) : AnyShapeStyle(.tertiary))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(name), \(isOn ? "on" : "off")")
                .accessibilityHint("Open room details")

                Toggle("", isOn: toggleBinding)
                    .toggleStyle(.switch)
                    .tint(.hueAccent)
                    .labelsHidden()
                    .disabled(groupedLightId == nil)
                    .accessibilityLabel("Toggle \(name)")
            }

            // Brightness slider (always visible for consistent card height)
            HStack(spacing: 4) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundStyle(isOn ? foreground.opacity(0.6) : .white.opacity(0.2))
                Slider(value: $sliderBrightness, in: 1...100) { editing in
                    isUserDragging = editing
                    if !editing {
                        commitBrightnessChange(sliderBrightness, immediately: true)
                    }
                }
                    .controlSize(.small)
                    .tint(isOn ? foreground.opacity(0.8) : .white.opacity(0.15))
                    .disabled(!isOn)
                    .accessibilityLabel("\(name) brightness")
                    .accessibilityValue("\(Int(sliderBrightness))%")
                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                    .foregroundStyle(isOn ? foreground.opacity(0.6) : .white.opacity(0.2))
            }
        }
        .padding(14)
        .modifier(ColorCardStyle(
            colors: isOn ? colors : nil, cornerRadius: 14, shadowOpacity: 0.3, shadowRadius: 6
        ))
        .padding(.horizontal)
        .onAppear {
            sliderBrightness = max(groupedLight?.displayBrightness ?? 0, 1)
        }
        .onChange(of: groupedLight?.displayBrightness) { _, newValue in
            if let newValue, !isUserDragging {
                sliderBrightness = max(newValue, 1)
            }
        }
        .onChange(of: sliderBrightness) { _, newValue in
            guard isUserDragging else { return }
            commitBrightnessChange(newValue)
        }
        .onDisappear { debounceTask?.cancel() }
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

    private func commitBrightnessChange(_ brightness: Double, immediately: Bool = false) {
        guard let id = groupedLightId else { return }
        apiClient.previewBrightness(groupedLightId: id, brightness: brightness)
        if immediately {
            debounceTask?.cancel()
            debounceTask = Task {
                try? await apiClient.setBrightness(groupedLightId: id, brightness: brightness)
            }
            return
        }

        debounce(task: &debounceTask) {
            try? await apiClient.setBrightness(groupedLightId: id, brightness: brightness)
        }
    }
}
