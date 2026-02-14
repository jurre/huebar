import Foundation
import Synchronization

/// Owns the SSE event stream lifecycle: connecting, parsing, reconnecting with backoff,
/// and yielding parsed HueEvent arrays via AsyncStream.
final class EventStreamConnection: Sendable {
    private let bridgeIP: String
    private let applicationKey: String
    private let session: URLSession

    private struct State {
        var task: Task<Void, Never>?
        var continuation: AsyncStream<[HueEvent]>.Continuation?
        var stream: AsyncStream<[HueEvent]>?
    }

    private let state = Mutex(State())

    init(bridgeIP: String, applicationKey: String, session: URLSession) {
        self.bridgeIP = bridgeIP
        self.applicationKey = applicationKey
        self.session = session
    }

    deinit {
        state.withLock { state in
            state.task?.cancel()
            state.continuation?.finish()
        }
    }

    /// Start listening for SSE events. Returns an AsyncStream of parsed event batches.
    /// Idempotent — multiple calls return the same stream.
    func start() -> AsyncStream<[HueEvent]> {
        state.withLock { state in
            if let existing = state.stream {
                return existing
            }

            let (stream, continuation) = AsyncStream<[HueEvent]>.makeStream(bufferingPolicy: .bufferingNewest(100))
            state.stream = stream
            state.continuation = continuation

            let bridgeIP = self.bridgeIP
            let applicationKey = self.applicationKey
            let session = self.session

            let task = Task {
                let parser = SSEParser()
                var backoff: UInt64 = 1

                while !Task.isCancelled {
                    parser.reset()

                    do {
                        var components = URLComponents()
                        components.scheme = "https"
                        components.host = bridgeIP
                        components.path = "/eventstream/clip/v2"
                        guard let url = components.url else { break }

                        var request = URLRequest(url: url)
                        request.setValue(applicationKey, forHTTPHeaderField: "hue-application-key")
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                        let (bytes, response) = try await session.bytes(for: request)
                        guard let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode == 200 else { throw HueAPIError.invalidResponse }

                        backoff = 1

                        var lineBuffer = Data()
                        for try await byte in bytes {
                            if byte == UInt8(ascii: "\n") {
                                let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                                lineBuffer.removeAll(keepingCapacity: true)
                                if let events = parser.processLine(line) {
                                    continuation.yield(events)
                                }
                            } else {
                                lineBuffer.append(byte)
                            }
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        do {
                            try await Task.sleep(nanoseconds: backoff * 1_000_000_000)
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
