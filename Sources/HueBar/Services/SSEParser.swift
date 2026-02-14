import Foundation

final class SSEParser {
    private var dataBuffer: [String] = []

    /// Feed one line at a time. Returns decoded events on blank-line boundaries.
    func processLine(_ line: String) -> [HueEvent]? {
        if line.isEmpty || line == "\r" {
            defer { dataBuffer.removeAll() }
            guard !dataBuffer.isEmpty else { return nil }

            let joined = dataBuffer.joined(separator: "\n")
            guard let data = joined.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([HueEvent].self, from: data)
        }

        if line.hasPrefix("data:") {
            let payload = if line.hasPrefix("data: ") {
                String(line.dropFirst(6))
            } else {
                String(line.dropFirst(5))
            }
            dataBuffer.append(payload)
        }
        // Comments (`:` prefix) and unknown fields (id:, event:, retry:) are ignored.
        return nil
    }

    /// Clear internal buffer (e.g. on reconnection).
    func reset() {
        dataBuffer.removeAll()
    }
}
