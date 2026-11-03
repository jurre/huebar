import Foundation
import Testing
@testable import HueBar

@Suite("EventStreamConnection")
struct EventStreamConnectionTests {

    // MARK: - Helpers

    /// Builds an ephemeral URLSession pointed at a non-routable IP so the connection
    /// fails immediately without actually reaching a network host.
    private func makeFailingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1
        config.timeoutIntervalForResource = 1
        return URLSession(configuration: config)
    }

    /// Race an async value against a timeout. Returns nil if the deadline expires.
    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @Sendable @escaping () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Tests

    @Test("stop() terminates the stream — iterator returns nil")
    func stopTerminatesStream() async {
        let connection = EventStreamConnection(
            bridgeIP: "192.0.2.1",   // TEST-NET, non-routable
            applicationKey: "test-key",
            session: makeFailingSession()
        )

        let stream = connection.start()
        connection.stop()

        let result = await withTimeout(seconds: 3) {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        // If we got a value back from withTimeout, the stream finished (next returned nil).
        // If withTimeout itself returned nil, the stream hung — stop() didn't work.
        #expect(result != nil, "Stream iterator should return (nil) promptly after stop(), not hang")
        // Unwrap: the inner next() should have returned nil
        if let inner = result {
            #expect(inner == nil, "Stream should finish after stop() is called")
        }
    }

    @Test("start() is idempotent — multiple calls return the same stream")
    func startIsIdempotent() async {
        let connection = EventStreamConnection(
            bridgeIP: "192.0.2.1",
            applicationKey: "test-key",
            session: makeFailingSession()
        )

        let stream1 = connection.start()
        let stream2 = connection.start()

        connection.stop()

        let result1 = await withTimeout(seconds: 3) {
            var it = stream1.makeAsyncIterator()
            return await it.next()
        }
        let result2 = await withTimeout(seconds: 3) {
            var it = stream2.makeAsyncIterator()
            return await it.next()
        }

        #expect(result1 != nil, "First stream should return promptly after stop(), not hang")
        #expect(result2 != nil, "Second stream should return promptly after stop(), not hang")
    }

    @Test("start() after stop() creates a new independent stream")
    func startAfterStopCreatesNewStream() async {
        let connection = EventStreamConnection(
            bridgeIP: "192.0.2.1",
            applicationKey: "test-key",
            session: makeFailingSession()
        )

        // First lifecycle
        let stream1 = connection.start()
        connection.stop()

        let result1 = await withTimeout(seconds: 3) {
            var it = stream1.makeAsyncIterator()
            return await it.next()
        }
        #expect(result1 != nil, "First stream should finish after stop()")

        // Second lifecycle — start() should create a new stream
        let stream2 = connection.start()
        connection.stop()

        let result2 = await withTimeout(seconds: 3) {
            var it = stream2.makeAsyncIterator()
            return await it.next()
        }
        #expect(result2 != nil, "New stream after stop()+start() should also work")
    }
}

// MARK: - Mock-based tests

/// URLProtocol subclass that serves pre-configured responses for testing EventStreamConnection.
private final class MockSSEProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(statusCode: Int, body: Data)] = []
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let index = Self.requestCount
        Self.requestCount += 1

        guard index < Self.responses.count else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        let (statusCode, body) = Self.responses[index]
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("EventStreamConnection with mock URLSession", .serialized)
struct EventStreamConnectionMockTests {

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSSEProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeSSEData(eventId: String = "ev-1") -> Data {
        let json = """
        [{"creationtime":"2024-01-01T00:00:00Z","id":"\(eventId)","type":"update","data":[{"id":"l-1","type":"light","on":{"on":true}}]}]
        """
        return "data: \(json)\n\n".data(using: .utf8)!
    }

    /// Race an async value against a timeout. Returns nil if the deadline expires.
    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @Sendable @escaping () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    @Test("Retries after failure and eventually yields events")
    func retriesAfterFailure() async {
        MockSSEProtocol.responses = [
            (500, Data()),        // First attempt: server error → triggers backoff
            (200, makeSSEData()), // Second attempt: success with SSE events
        ]
        MockSSEProtocol.requestCount = 0

        let connection = EventStreamConnection(
            bridgeIP: "192.0.2.1",
            applicationKey: "test-key",
            session: makeMockSession()
        )

        let stream = connection.start()

        // Should get events after the retry (backoff is 1s for first retry)
        let result = await withTimeout(seconds: 5) {
            var it = stream.makeAsyncIterator()
            while let message = await it.next() {
                if case .events(let events) = message {
                    return events
                }
            }
            return []
        }

        connection.stop()

        #expect(result != nil, "Should receive events after retrying past the failure")
        if let events = result {
            #expect(events.count == 1)
            #expect(events[0].id == "ev-1")
        }
        #expect(MockSSEProtocol.requestCount >= 2, "Should have made at least 2 requests (1 failure + 1 success)")
    }

    @Test("Only one connection is created when start() is called multiple times")
    func startCreatesOneConnection() async {
        // Brief yield to drain any in-flight URLProtocol requests from prior tests,
        // since task cancellation is cooperative and requests may still be pending.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Use a failing response so the connection enters backoff (1s) after the first request.
        // If start() created duplicate connections, we'd see requestCount > 1 before backoff expires.
        MockSSEProtocol.responses = [
            (500, Data()),
        ]
        MockSSEProtocol.requestCount = 0

        let connection = EventStreamConnection(
            bridgeIP: "192.0.2.1",
            applicationKey: "test-key",
            session: makeMockSession()
        )

        _ = connection.start()
        _ = connection.start()

        // Wait less than the 1s backoff — only the initial request should have been made
        try? await Task.sleep(nanoseconds: 200_000_000)

        let count = MockSSEProtocol.requestCount
        connection.stop()

        #expect(count == 1, "Two start() calls should only create one connection, got \(count)")
    }

    @Test("Yields reconnected once the stream is re-established after a clean close")
    func yieldsReconnectedAfterCleanClose() async {
        MockSSEProtocol.responses = [
            (200, makeSSEData(eventId: "ev-1")), // Closed by the server after one event
            (200, makeSSEData(eventId: "ev-2")),
        ]
        MockSSEProtocol.requestCount = 0

        let connection = EventStreamConnection(
            bridgeIP: "192.0.2.1",
            applicationKey: "test-key",
            session: makeMockSession()
        )
        let stream = connection.start()

        let received = await withTimeout(seconds: 5) {
            var received: [String] = []
            var it = stream.makeAsyncIterator()
            while let message = await it.next() {
                switch message {
                case .reconnected:
                    received.append("reconnected")
                case .events(let events):
                    received.append(contentsOf: events.map(\.id))
                }
                if received.last == "ev-2" { break }
            }
            return received
        }

        connection.stop()

        #expect(received == ["ev-1", "reconnected", "ev-2"])
    }

    @Test("Backs off instead of reconnecting immediately when the bridge keeps closing the stream")
    func backsOffWhenStreamKeepsClosingImmediately() async {
        // Drain in-flight requests from prior tests before resetting the counter.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Every attempt gets a 200 and is then closed by the server right away.
        MockSSEProtocol.responses = Array(repeating: (200, Data(": hi\n\n".utf8)), count: 500)
        MockSSEProtocol.requestCount = 0

        let connection = EventStreamConnection(
            bridgeIP: "192.0.2.1",
            applicationKey: "test-key",
            session: makeMockSession()
        )
        let stream = connection.start()
        let reader = Task {
            var reconnects = 0
            for await message in stream {
                if case .reconnected = message { reconnects += 1 }
            }
            return reconnects
        }

        try? await Task.sleep(nanoseconds: 1_500_000_000)
        connection.stop()
        let requestCount = MockSSEProtocol.requestCount
        let reconnects = await reader.value

        // First attempt at t=0, the second only after the 1s back-off.
        #expect(requestCount <= 3, "Should back off between reconnects, got \(requestCount) requests in 1.5s")
        #expect(reconnects <= 2, "Should not trigger a resync per reconnect attempt, got \(reconnects)")
    }
}
