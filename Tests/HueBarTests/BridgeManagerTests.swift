import Foundation
import Testing

@testable import HueBar

// Extension of CredentialStoreTests so bridge manager tests share
// the same serialized suite and storageDirectory lifecycle.
extension CredentialStoreTests {
    private func makeCredentials(id: String, ip: String = "192.168.1.10", name: String = "Bridge") -> BridgeCredentials {
        BridgeCredentials(id: id, bridgeIP: ip, applicationKey: "test-key-\(id)", name: name)
    }

    @Test func addBridgeCreatesBridge() throws {
        let manager = BridgeManager()
        manager.addBridge(credentials: makeCredentials(id: "bridge-1", name: "Office"))

        #expect(manager.bridges.count == 1)
        #expect(manager.bridges[0].id == "bridge-1")
        #expect(manager.bridges[0].name == "Office")
    }

    @Test func addDuplicateBridgeIsIgnored() throws {
        let manager = BridgeManager()
        let creds = makeCredentials(id: "dup-bridge")
        manager.addBridge(credentials: creds)
        manager.addBridge(credentials: creds)

        #expect(manager.bridges.count == 1)
    }

    @Test func removeBridgeDisconnectsAndRemoves() throws {
        defer {
            try? FileManager.default.removeItem(
                at: CredentialStore.storageDirectory.appendingPathComponent("bridges.json"))
        }
        let manager = BridgeManager()
        manager.addBridge(credentials: makeCredentials(id: "keep", ip: "192.168.1.10", name: "Keep"))
        manager.addBridge(credentials: makeCredentials(id: "drop", ip: "192.168.1.11", name: "Drop"))
        #expect(manager.bridges.count == 2)

        manager.removeBridge(id: "drop")

        #expect(manager.bridges.count == 1)
        #expect(manager.bridges[0].id == "keep")
    }

    @Test func bridgeForIdReturnsCorrectBridge() throws {
        let manager = BridgeManager()
        manager.addBridge(credentials: makeCredentials(id: "alpha", ip: "192.168.1.10", name: "Alpha"))
        manager.addBridge(credentials: makeCredentials(id: "beta", ip: "192.168.1.11", name: "Beta"))

        let found = manager.bridge(for: "beta")
        #expect(found?.id == "beta")
        #expect(found?.name == "Beta")

        #expect(manager.bridge(for: "nonexistent") == nil)
    }

    @Test func loadBridgesAndAddToManager() throws {
        defer {
            try? FileManager.default.removeItem(
                at: CredentialStore.storageDirectory.appendingPathComponent("bridges.json"))
        }
        try CredentialStore.saveBridge(makeCredentials(id: "stored-1", ip: "192.168.1.10", name: "First"))
        try CredentialStore.saveBridge(makeCredentials(id: "stored-2", ip: "192.168.1.11", name: "Second"))

        let manager = BridgeManager()
        let credentials = CredentialStore.loadBridges()
        for cred in credentials {
            manager.addBridge(credentials: cred)
        }

        #expect(manager.bridges.count == 2)
        let ids = Set(manager.bridges.map(\.id))
        #expect(ids == ["stored-1", "stored-2"])
    }

    @Test func bridgeConnectionRetriesAfterTransientNetworkFailure() async throws {
        // Arrange
        let context = createRetryTestContext()
        defer { BridgeConnectionRetryURLProtocol.requestHandler = nil }

        // Act
        await context.connection.connect()

        // Assert
        guard case .error = context.connection.status else {
            Issue.record("Expected first connection attempt to fail")
            return
        }
        #expect(context.client.lastError != nil)

        try await Task.sleep(for: .milliseconds(100))

        #expect(context.connection.status == .connected)
        #expect(context.client.lastError == nil)
        #expect(context.requestCount() >= 10)

        context.connection.disconnect()
    }

    @Test func bridgeConnectionRefreshUpdatesConnectedBridgeState() async throws {
        // Arrange
        let context = createRefreshTestContext(groupedLightIsOn: true)
        defer { BridgeConnectionRetryURLProtocol.requestHandler = nil }
        context.connection.status = .connected
        context.client.groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: false), dimming: DimmingState(brightness: 0), colorTemperature: nil),
        ]

        // Act
        await context.connection.refresh()

        // Assert
        #expect(context.connection.status == .connected)
        #expect(context.client.groupedLights.first?.isOn == true)
        #expect(context.client.groupedLights.first?.brightness == 75)
        #expect(context.requestCount() == 5)
    }

    @Test func bridgeConnectionRefreshSkipsConnectedBridgeWithinCooldown() async throws {
        // Arrange
        var currentDate = Date(timeIntervalSince1970: 100)
        let context = createRefreshTestContext(
            groupedLightIsOn: true,
            minimumRefreshInterval: 30,
            currentDate: { currentDate }
        )
        defer { BridgeConnectionRetryURLProtocol.requestHandler = nil }
        context.connection.status = .connected
        context.client.groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: false), dimming: DimmingState(brightness: 0), colorTemperature: nil),
        ]

        // Act
        await context.connection.refresh()
        context.client.groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: false), dimming: DimmingState(brightness: 0), colorTemperature: nil),
        ]
        currentDate = Date(timeIntervalSince1970: 110)
        await context.connection.refresh()
        let requestCountAfterCooldownSkip = context.requestCount()
        let isOnAfterCooldownSkip = context.client.groupedLights.first?.isOn
        currentDate = Date(timeIntervalSince1970: 131)
        await context.connection.refresh()

        // Assert
        #expect(requestCountAfterCooldownSkip == 5)
        #expect(isOnAfterCooldownSkip == false)
        #expect(context.connection.status == .connected)
        #expect(context.client.groupedLights.first?.isOn == true)
        #expect(context.client.groupedLights.first?.brightness == 75)
        #expect(context.requestCount() == 10)
    }

    @Test func bridgeManagerRefreshAllRefreshesConnectedBridges() async throws {
        // Arrange
        let context = createRefreshTestContext(groupedLightIsOn: true)
        defer { BridgeConnectionRetryURLProtocol.requestHandler = nil }
        context.connection.status = .connected
        context.client.groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: false), dimming: DimmingState(brightness: 0), colorTemperature: nil),
        ]
        let manager = BridgeManager(bridges: [context.connection])

        // Act
        await manager.refreshAll()

        // Assert
        #expect(context.client.groupedLights.first?.isOn == true)
        #expect(context.requestCount() == 5)
    }

    @Test func bridgeConnectionRetryDelayDoublesThenCaps() {
        let base = Duration.seconds(5)
        let cap = Duration.seconds(60)
        #expect(BridgeConnection.computeRetryDelay(attempt: 0, initial: base, maximum: cap) == .seconds(5))
        #expect(BridgeConnection.computeRetryDelay(attempt: 1, initial: base, maximum: cap) == .seconds(10))
        #expect(BridgeConnection.computeRetryDelay(attempt: 2, initial: base, maximum: cap) == .seconds(20))
        #expect(BridgeConnection.computeRetryDelay(attempt: 3, initial: base, maximum: cap) == .seconds(40))
        // 5 * 2^4 = 80s, capped to 60s.
        #expect(BridgeConnection.computeRetryDelay(attempt: 4, initial: base, maximum: cap) == .seconds(60))
        #expect(BridgeConnection.computeRetryDelay(attempt: 10, initial: base, maximum: cap) == .seconds(60))
        // Defensive: huge attempt counts must not overflow.
        #expect(BridgeConnection.computeRetryDelay(attempt: 10_000, initial: base, maximum: cap) == .seconds(60))
        // Defensive: negative attempts collapse to the initial delay.
        #expect(BridgeConnection.computeRetryDelay(attempt: -5, initial: base, maximum: cap) == .seconds(5))
        // Defensive: initial >= maximum returns the cap immediately.
        #expect(
            BridgeConnection.computeRetryDelay(attempt: 0, initial: .seconds(120), maximum: .seconds(60))
                == .seconds(60)
        )
    }

    private func createRefreshTestContext(
        groupedLightIsOn: Bool,
        minimumRefreshInterval: TimeInterval = 30,
        currentDate: @escaping @MainActor () -> Date = Date.init
    ) -> (
        connection: BridgeConnection,
        client: HueAPIClient,
        requestCount: () -> Int
    ) {
        createBridgeConnectionContext { request, _ in
            let path = request.url?.path ?? ""
            let json: String
            if path.hasSuffix("/room") {
                json = #"{"errors":[],"data":[{"id":"room-1","metadata":{"name":"Office","archetype":"office"},"services":[{"rid":"gl-1","rtype":"grouped_light"}],"children":[]}]}"#
            } else if path.hasSuffix("/grouped_light") {
                json = #"{"errors":[],"data":[{"id":"gl-1","on":{"on":\#(groupedLightIsOn)},"dimming":{"brightness":75.0}}]}"#
            } else {
                json = #"{"errors":[],"data":[]}"#
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        } makeConnection: { client in
            BridgeConnection(
                id: "office-bridge",
                name: "Office Bridge",
                client: client,
                initialRetryDelay: .milliseconds(10),
                minimumRefreshInterval: minimumRefreshInterval,
                currentDate: currentDate
            )
        }
    }

    private func createRetryTestContext() -> (
        connection: BridgeConnection,
        client: HueAPIClient,
        requestCount: () -> Int
    ) {
        createBridgeConnectionContext { request, currentRequestCount in
            if currentRequestCount <= 5 {
                throw URLError(.notConnectedToInternet)
            }

            let path = request.url?.path ?? ""
            let json: String
            if path.hasSuffix("/room") {
                json = #"{"errors":[],"data":[{"id":"room-1","metadata":{"name":"Office","archetype":"office"},"services":[{"rid":"gl-1","rtype":"grouped_light"}],"children":[]}]}"#
            } else if path.hasSuffix("/grouped_light") {
                json = #"{"errors":[],"data":[{"id":"gl-1","on":{"on":true},"dimming":{"brightness":75.0}}]}"#
            } else {
                json = #"{"errors":[],"data":[]}"#
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }

    private func createBridgeConnectionContext(
        handler: @escaping @Sendable (URLRequest, Int) throws -> (HTTPURLResponse, Data),
        makeConnection: ((HueAPIClient) -> BridgeConnection)? = nil
    ) -> (
        connection: BridgeConnection,
        client: HueAPIClient,
        requestCount: () -> Int
    ) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BridgeConnectionRetryURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = HueAPIClient(bridgeIP: "127.0.0.1:1234", applicationKey: "test-key", session: session)

        let lock = NSLock()
        var requestCount = 0
        BridgeConnectionRetryURLProtocol.requestHandler = { request in
            lock.lock()
            requestCount += 1
            let currentRequestCount = requestCount
            lock.unlock()

            return try handler(request, currentRequestCount)
        }

        let connection = makeConnection?(client) ?? BridgeConnection(
            id: "office-bridge",
            name: "Office Bridge",
            client: client,
            initialRetryDelay: .milliseconds(10)
        )

        return (
            connection: connection,
            client: client,
            requestCount: {
                lock.lock()
                defer { lock.unlock() }
                return requestCount
            }
        )
    }
}

private final class BridgeConnectionRetryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
