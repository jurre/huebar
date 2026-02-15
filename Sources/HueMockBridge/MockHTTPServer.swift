import Foundation
import Network

/// Minimal HTTP server using Network framework.
final class MockHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let handler: @Sendable (HTTPRequest) -> HTTPResponse
    private let queue = DispatchQueue(label: "mock-http-server")

    init(port: UInt16, handler: @escaping @Sendable (HTTPRequest) -> HTTPResponse) throws {
        let params = NWParameters.tcp
        self.listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.handler = handler
    }

    func start() {
        listener.newConnectionHandler = { [handler] connection in
            connection.start(queue: DispatchQueue(label: "mock-conn-\(connection.endpoint)"))
            Self.receiveRequest(connection: connection, handler: handler)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("Server error: \(error)")
            }
        }
        listener.start(queue: queue)
    }

    private static func receiveRequest(
        connection: NWConnection,
        handler: @escaping @Sendable (HTTPRequest) -> HTTPResponse
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, let requestString = String(data: data, encoding: .utf8) {
                let request = HTTPRequest.parse(requestString)
                let response = handler(request)
                let responseData = response.serialize()
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    if response.isSSE {
                        // Keep SSE connections open — send periodic events
                        Self.streamSSE(connection: connection)
                    } else {
                        connection.cancel()
                    }
                })
            } else if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private static func streamSSE(connection: NWConnection) {
        // Send an empty keepalive every 10 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            let keepalive = Data(": keepalive\n\n".utf8)
            connection.send(content: keepalive, completion: .contentProcessed { error in
                if error == nil {
                    Self.streamSSE(connection: connection)
                }
            })
        }
    }
}

// MARK: - HTTP Request

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: String?

    static func parse(_ raw: String) -> HTTPRequest {
        let lines = raw.components(separatedBy: "\r\n")
        let requestLine = lines[0].components(separatedBy: " ")
        let method = requestLine.count > 0 ? requestLine[0] : "GET"
        let path = requestLine.count > 1 ? requestLine[1] : "/"

        var headers: [String: String] = [:]
        var bodyStart = false
        var bodyLines: [String] = []
        for line in lines.dropFirst() {
            if line.isEmpty {
                bodyStart = true
                continue
            }
            if bodyStart {
                bodyLines.append(line)
            } else if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: bodyLines.isEmpty ? nil : bodyLines.joined(separator: "\n")
        )
    }
}

// MARK: - HTTP Response

struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let isSSE: Bool

    init(statusCode: Int = 200, contentType: String = "application/json", body: Data, isSSE: Bool = false) {
        var headers = ["Content-Type": contentType]
        if isSSE {
            headers["Content-Type"] = "text/event-stream"
            headers["Cache-Control"] = "no-cache"
            headers["Connection"] = "keep-alive"
        } else {
            headers["Content-Length"] = "\(body.count)"
        }
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.isSSE = isSSE
    }

    static func json(_ value: Any, statusCode: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
        return HTTPResponse(body: data)
    }

    static func sse() -> HTTPResponse {
        // Initial SSE response with empty data — connection stays open
        let initial = Data("data: []\n\n".utf8)
        return HTTPResponse(body: initial, isSSE: true)
    }

    func serialize() -> Data {
        var result = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        for (key, value) in headers {
            result += "\(key): \(value)\r\n"
        }
        result += "\r\n"
        return Data(result.utf8) + body
    }

    private var statusText: String {
        switch statusCode {
        case 200: "OK"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "OK"
        }
    }
}
