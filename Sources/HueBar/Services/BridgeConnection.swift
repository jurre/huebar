import Foundation

enum BridgeConnectionStatus: Sendable, Equatable {
    case connecting
    case connected
    case error(String)
}

@Observable
@MainActor
final class BridgeConnection: Identifiable {
    let id: String
    var name: String
    let client: HueAPIClient
    var status: BridgeConnectionStatus = .connecting

    init(credentials: BridgeCredentials) throws {
        self.id = credentials.id
        self.name = credentials.name
        self.client = try HueAPIClient(bridgeIP: credentials.bridgeIP, applicationKey: credentials.applicationKey)
    }

    /// Connect to the bridge: fetch all data and start event stream
    func connect() async {
        guard status != .connected, status != .connecting else { return }
        status = .connecting
        await client.fetchAll()
        if let error = client.lastError {
            status = .error(error)
        } else {
            status = .connected
            client.startEventStream()
        }
    }

    /// Disconnect from the bridge
    func disconnect() {
        client.stopEventStream()
    }
}
