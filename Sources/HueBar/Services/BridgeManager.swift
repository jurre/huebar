import Foundation

@Observable
@MainActor
final class BridgeManager {
    private(set) var bridges: [BridgeConnection] = []

    /// Whether any bridge is currently loading
    var isLoading: Bool {
        bridges.contains { $0.status == .disconnected || $0.status == .connecting }
    }

    /// Load credentials and connect to all stored bridges
    func loadAndConnect() async {
        let credentials = CredentialStore.loadBridges()
        for cred in credentials {
            await addAndConnect(credentials: cred)
        }
    }

    /// Add a new bridge from credentials and connect
    func addAndConnect(credentials: BridgeCredentials) async {
        guard addBridge(credentials: credentials) != nil else { return }
        await bridges.last?.connect()
    }

    /// Add a bridge without connecting (used by tests and when building the array before connecting)
    @discardableResult
    func addBridge(credentials: BridgeCredentials) -> BridgeConnection? {
        guard !bridges.contains(where: { $0.id == credentials.id }) else { return nil }
        do {
            let connection = try BridgeConnection(credentials: credentials)
            bridges.append(connection)
            return connection
        } catch {
            return nil
        }
    }

    /// Remove a bridge and disconnect
    func removeBridge(id: String) {
        guard let index = bridges.firstIndex(where: { $0.id == id }) else { return }
        bridges[index].disconnect()
        bridges.remove(at: index)
        try? CredentialStore.removeBridge(id: id)
    }

    /// Get a specific bridge connection by ID
    func bridge(for id: String) -> BridgeConnection? {
        bridges.first(where: { $0.id == id })
    }

    /// Disconnect all bridges
    func disconnectAll() {
        for bridge in bridges {
            bridge.disconnect()
        }
    }

    /// Disconnect and remove all bridges (sign out)
    func removeAll() {
        disconnectAll()
        for bridge in bridges {
            try? CredentialStore.removeBridge(id: bridge.id)
        }
        bridges.removeAll()
    }

    /// Connect all bridges that aren't already connected
    func connectAll() async {
        for bridge in bridges {
            await bridge.connect()
        }
    }
}
