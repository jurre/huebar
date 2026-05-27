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
    /// Base delay before the first reconnect attempt after a failure.
    private let initialRetryDelay: Duration
    /// Upper bound on the reconnect delay; exponential growth is clamped here.
    private let maxRetryDelay: Duration
    /// Number of consecutive failed connection attempts since the last successful connect.
    @ObservationIgnored private var retryAttempt: Int = 0
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?

    init(
        credentials: BridgeCredentials,
        initialRetryDelay: Duration = .seconds(5),
        maxRetryDelay: Duration = .seconds(300)
    ) throws {
        self.id = credentials.id
        self.name = credentials.name
        self.initialRetryDelay = initialRetryDelay
        self.maxRetryDelay = maxRetryDelay
        self.client = try HueAPIClient(bridgeIP: credentials.bridgeIP, applicationKey: credentials.applicationKey)
    }

    init(
        id: String,
        name: String,
        client: HueAPIClient,
        initialRetryDelay: Duration = .seconds(5),
        maxRetryDelay: Duration = .seconds(300)
    ) {
        self.id = id
        self.name = name
        self.client = client
        self.initialRetryDelay = initialRetryDelay
        self.maxRetryDelay = maxRetryDelay
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
            retryAttempt = 0
            client.startEventStream()
        }
    }

    /// Disconnect from the bridge
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        retryAttempt = 0
        client.stopEventStream()
    }

    /// Compute an exponentially growing retry delay, capped at `maximum`.
    /// Pure function exposed for unit testing the back-off curve.
    static func computeRetryDelay(attempt: Int, initial: Duration, maximum: Duration) -> Duration {
        // Treat any negative attempt as the first attempt so callers can't accidentally negate the back-off.
        let safeAttempt = max(0, attempt)
        // Once the cap dominates, stop scaling — this also prevents `1 << exponent` from blowing past Int64.
        guard initial > .zero, initial < maximum else { return maximum }
        var delay = initial
        for _ in 0..<safeAttempt {
            delay = delay * 2
            if delay >= maximum { return maximum }
        }
        return delay
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = Self.computeRetryDelay(
            attempt: retryAttempt,
            initial: initialRetryDelay,
            maximum: maxRetryDelay
        )
        retryAttempt += 1
        reconnectTask = Task { [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
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
