import Foundation
import os

@MainActor
final class GroupColorChange {
    private static let logger = Logger(subsystem: "com.huebar", category: "GroupColorChange")

    private struct Pending {
        let client: HueAPIClient
        let id: String
        let lightIds: [String]
        let xy: CIEXYColor
        let previewToken: UUID
    }

    private var pending: Pending?
    private var debounceTask: Task<Void, Never>?

    func schedule(client: HueAPIClient, id: String, lightIds: [String], xy: CIEXYColor) {
        if let pending, pending.client !== client || pending.id != id || pending.lightIds != lightIds {
            flush()
        }
        debounceTask?.cancel()
        let token = client.previewGroupedLightColor(lightIds: lightIds, xy: xy)
        pending = Pending(client: client, id: id, lightIds: lightIds, xy: xy, previewToken: token)
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Finish the last selection on navigation. Only the delay is cancellable, never a started PUT.
    @discardableResult
    func flush() -> Task<Void, Never>? {
        debounceTask?.cancel()
        debounceTask = nil
        guard let pending else { return nil }
        self.pending = nil
        return Task {
            do {
                try await pending.client.setGroupedLightColor(
                    id: pending.id, xy: pending.xy, lightIds: pending.lightIds, previewToken: pending.previewToken
                )
            } catch {
                Self.logger.error("Failed to set color for grouped light \(pending.id): \(error.localizedDescription)")
            }
        }
    }
}
