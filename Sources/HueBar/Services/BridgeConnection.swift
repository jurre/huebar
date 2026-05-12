import Foundation
import Observation

enum BridgeConnectionStatus: Sendable, Equatable {
    case disconnected
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
    var status: BridgeConnectionStatus = .disconnected
    private let retryDelay: Duration
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?

    init(credentials: BridgeCredentials, retryDelay: Duration = .seconds(5)) throws {
        self.id = credentials.id
        self.name = credentials.name
        self.retryDelay = retryDelay
        self.client = try HueAPIClient(bridgeIP: credentials.bridgeIP, applicationKey: credentials.applicationKey)
    }

    init(id: String, name: String, client: HueAPIClient, retryDelay: Duration = .seconds(5)) {
        self.id = id
        self.name = name
        self.client = client
        self.retryDelay = retryDelay
    }

    /// Connect to the bridge: fetch all data and start event stream
    func connect() async {
        guard status != .connected, status != .connecting else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        status = .connecting
        await client.fetchAll()
        if let error = client.lastError {
            status = .error(error)
            scheduleReconnect()
        } else {
            status = .connected
            client.startEventStream()
        }
    }

    /// Disconnect from the bridge
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        client.stopEventStream()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self, retryDelay] in
            do {
                try await Task.sleep(for: retryDelay)
            } catch {
                return
            }
            await self?.retryConnection()
        }
    }

    private func retryConnection() async {
        reconnectTask = nil
        await connect()
    }
}
