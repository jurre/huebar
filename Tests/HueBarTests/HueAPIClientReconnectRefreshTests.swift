import Foundation
import Testing
@testable import HueBar

/// Serves each response after a per-request delay without blocking `startLoading`, so a slow
/// response can stay in flight while later requests complete.
private final class DelayedURLProtocol: URLProtocol, @unchecked Sendable {
    // SAFETY: Assigned on the main actor before a test issues any request and only read afterwards
    // from URLSession's loading threads. The suite is serialized and every test installs its own responder.
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (delay: TimeInterval, body: String))?

    private let lock = NSLock()
    private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let (delay, body) = Self.responder?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            lock.lock()
            let stopped = isStopped
            lock.unlock()
            guard !stopped,
                  let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        lock.lock()
        isStopped = true
        lock.unlock()
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private let groupedLightId = "00000000-0000-0000-0000-000000000099"
private let emptyEnvelope = #"{"errors":[],"data":[]}"#

private func groupedLightEnvelope(isOn: Bool) -> String {
    #"{"errors":[],"data":[{"id":"\#(groupedLightId)","on":{"on":\#(isOn)},"dimming":{"brightness":80.0}}]}"#
}

@MainActor
private func makeClient() -> HueAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DelayedURLProtocol.self]
    return HueAPIClient(bridgeIP: "192.168.1.100", applicationKey: "test-key", session: URLSession(configuration: config))
}

private func makeAddEvent() -> HueEvent {
    HueEvent(creationtime: "2024-01-01T00:00:00Z", id: UUID().uuidString, type: .add, data: [])
}

@Suite(.serialized)
@MainActor
struct HueAPIClientReconnectRefreshTests {
    @Test func reconnectRefreshSupersedesPendingDebouncedRefresh() async throws {
        // Arrange
        let client = makeClient()
        let groupedLightRequests = RequestCounter()
        DelayedURLProtocol.responder = { request in
            guard request.url?.path.hasSuffix("/grouped_light") == true else { return (0, emptyEnvelope) }
            groupedLightRequests.increment()
            return (0, groupedLightEnvelope(isOn: true))
        }
        defer { client.stopEventStream() }

        // Act
        client.applyEvents([makeAddEvent()])
        await client.handleEventStreamMessage(.reconnected)
        try await Task.sleep(for: .milliseconds(800))

        // Assert
        #expect(groupedLightRequests.count == 1)
    }

    @Test func reconnectRefreshWinsOverInFlightDebouncedRefresh() async throws {
        // Arrange
        let client = makeClient()
        let groupedLightRequests = RequestCounter()
        DelayedURLProtocol.responder = { request in
            guard request.url?.path.hasSuffix("/grouped_light") == true else { return (0, emptyEnvelope) }
            let isDebouncedRefresh = groupedLightRequests.increment() == 1
            return isDebouncedRefresh
                ? (0.6, groupedLightEnvelope(isOn: false))
                : (0, groupedLightEnvelope(isOn: true))
        }
        defer { client.stopEventStream() }

        // Act
        client.applyEvents([makeAddEvent()])
        let debouncedRefreshStarted = await waitUntil { groupedLightRequests.count == 1 }
        await client.handleEventStreamMessage(.reconnected)
        try await Task.sleep(for: .milliseconds(800))

        // Assert
        #expect(debouncedRefreshStarted)
        #expect(client.groupedLights.first?.isOn == true)
        #expect(client.lastError == nil)
    }

    private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async -> Bool {
        for _ in 0..<80 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
