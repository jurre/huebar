import Foundation

extension HueAPIClient {

    func startEventStream() {
        guard eventStreamTask == nil else { return }
        eventStreamTask = Task { await runEventStream() }
    }

    func stopEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
    }

    private func runEventStream() async {
        let parser = SSEParser()
        var backoff: UInt64 = 1

        while !Task.isCancelled {
            parser.reset()

            do {
                var components = URLComponents()
                components.scheme = "https"
                components.host = bridgeIP
                components.path = "/eventstream/clip/v2"
                guard let url = components.url else { continue }

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
                            applyEvents(events)
                        }
                    } else {
                        lineBuffer.append(byte)
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                // Sleep with exponential backoff before retrying
                do {
                    try await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                } catch { break }
                backoff = min(backoff * 2, 30)
            }
        }
    }

    func applyEvents(_ events: [HueEvent]) {
        for event in events {
            switch event.type {
            case .update:
                for resource in event.data {
                    switch resource.type {
                    case "grouped_light":
                        EventStreamUpdater.apply(resource, to: &groupedLights)
                    case "light":
                        EventStreamUpdater.apply(resource, to: &lights)
                    case "scene":
                        if resource.status?.active == .static {
                            activeSceneId = resource.id
                        }
                    default:
                        break
                    }
                }
            case .add, .delete:
                Task { await fetchAll() }
            }
        }
    }
}
