import Foundation

@MainActor
func debounce(
    task: inout Task<Void, Never>?,
    duration: Duration = .milliseconds(200),
    action: @escaping @MainActor () async -> Void
) {
    task?.cancel()
    task = Task {
        try? await Task.sleep(for: duration)
        guard !Task.isCancelled else { return }
        await action()
    }
}
