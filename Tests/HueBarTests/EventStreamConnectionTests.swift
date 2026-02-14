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

    private func makeSSEData() -> Data {
        let json = """
        [{"creationtime":"2024-01-01T00:00:00Z","id":"ev-1","type":"update","data":[{"id":"l-1","type":"light","on":{"on":true}}]}]
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
            return await it.next()
        }

        connection.stop()

        #expect(result != nil, "Should receive events after retrying past the failure")
        if let events = result {
            #expect(events != nil, "Events batch should not be nil")
            if let events {
                #expect(events.count == 1)
                #expect(events[0].id == "ev-1")
            }
        }
        #expect(MockSSEProtocol.requestCount >= 2, "Should have made at least 2 requests (1 failure + 1 success)")
    }

    @Test("Only one connection is created when start() is called multiple times")
    func startCreatesOneConnection() async {
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
}
