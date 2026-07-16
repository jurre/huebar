import Foundation
import os
import Synchronization

private let logger = Logger(subsystem: "com.huebar", category: "EventStreamConnection")

enum EventStreamMessage: Sendable {
    case reconnected
    case events([HueEvent])
}

/// Owns the SSE event stream lifecycle: connecting, parsing, reconnecting with backoff,
/// and yielding parsed HueEvent arrays via AsyncStream.
final class EventStreamConnection: Sendable {
    private let bridgeIP: String
    private let applicationKey: String
    private let session: URLSession
    private let parsedHost: String
    private let parsedPort: Int?

    private var isLocalMock: Bool {
        parsedHost == "127.0.0.1" || parsedHost == "localhost"
    }

    private var scheme: String { isLocalMock ? "http" : "https" }

    private struct State {
        var task: Task<Void, Never>?
        var continuation: AsyncStream<EventStreamMessage>.Continuation?
        var stream: AsyncStream<EventStreamMessage>?
    }

    private let state = Mutex(State())

    init(bridgeIP: String, applicationKey: String, session: URLSession) {
        let parsed = IPValidation.parseHostPort(bridgeIP)
        self.bridgeIP = bridgeIP
        self.applicationKey = applicationKey
        self.session = session
        self.parsedHost = parsed.host
        self.parsedPort = parsed.port
    }

    deinit {
        state.withLock { state in
            state.task?.cancel()
            state.continuation?.finish()
        }
    }

    /// Start listening for SSE events. Returns an AsyncStream of parsed event batches.
    /// Idempotent — multiple calls return the same stream.
    func start() -> AsyncStream<EventStreamMessage> {
        state.withLock { state in
            if let existing = state.stream {
                return existing
            }

            let (stream, continuation) = AsyncStream<EventStreamMessage>.makeStream(bufferingPolicy: .bufferingNewest(100))
            state.stream = stream
            state.continuation = continuation

            let bridgeIP = self.bridgeIP
            let applicationKey = self.applicationKey
            let session = self.session
            let scheme = self.scheme
            let host = self.parsedHost
            let port = self.parsedPort

            let task = Task {
                let parser = SSEParser()
                var backoff: UInt64 = 1
                var shouldResyncOnConnect = false

                while !Task.isCancelled {
                    parser.reset()

                    do {
                        var components = URLComponents()
                        components.scheme = scheme
                        components.host = host
                        components.port = port
                        components.path = "/eventstream/clip/v2"
                        guard let url = components.url else { break }

                        var request = URLRequest(url: url)
                        request.setValue(applicationKey, forHTTPHeaderField: "hue-application-key")
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                        let (bytes, response) = try await session.bytes(for: request)
                        guard let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode == 200 else { throw HueAPIError.invalidResponse }

                        if shouldResyncOnConnect {
                            continuation.yield(.reconnected)
                            shouldResyncOnConnect = false
                        }
                        backoff = 1

                        var lineBuffer = Data()
                        for try await byte in bytes {
                            if byte == UInt8(ascii: "\n") {
                                let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                                lineBuffer.removeAll(keepingCapacity: true)
                                if let events = parser.processLine(line) {
                                    continuation.yield(.events(events))
                                }
                            } else {
                                lineBuffer.append(byte)
                            }
                        }
                        shouldResyncOnConnect = true
                    } catch is CancellationError {
                        break
                    } catch {
                        logger.error("Event stream connection failed for \(bridgeIP, privacy: .private): \(error.localizedDescription, privacy: .public)")
                        shouldResyncOnConnect = true
                        do {
                            try await Task.sleep(for: .seconds(backoff))
                        } catch { break }
                        backoff = min(backoff * 2, 30)
                    }
                }

                continuation.finish()
            }

            state.task = task
            continuation.onTermination = { _ in task.cancel() }

            return stream
        }
    }

    /// Stop the event stream connection and finish the AsyncStream.
    func stop() {
        state.withLock { state in
            state.task?.cancel()
            state.continuation?.finish()
            state.task = nil
            state.continuation = nil
            state.stream = nil
        }
    }
}
