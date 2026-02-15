import Foundation

@main
struct HueMockBridgeMain {
    static func main() throws {
        // Line-buffer stdout so logs appear immediately even when piped
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        let args = CommandLine.arguments

        // Parse flags
        var port: UInt16 = 8080
        var name = "Mock Bridge"
        var roomDefs: [MockRoomDef]?

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--port", "-p":
                i += 1
                if i < args.count, let p = UInt16(args[i]), p > 0 {
                    port = p
                } else {
                    let value = (i < args.count) ? args[i] : "<missing>"
                    fputs("Error: invalid port '\(value)'. Port must be a positive integer.\n\n", stderr)
                    printUsage()
                    exit(1)
                }
            case "--name", "-n":
                i += 1
                if i < args.count { name = args[i] }
            case "--rooms", "-r":
                // Format: "Name:archetype:count,Name:archetype:count,..."
                i += 1
                if i < args.count { roomDefs = parseRooms(args[i]) }
            case "--help", "-h":
                printUsage()
                return
            default:
                break
            }
            i += 1
        }

        let bridge = MockBridge(name: name, rooms: roomDefs ?? MockRoomDef.defaults)

        let server = try MockHTTPServer(port: port) { request in
            return bridge.handleRequest(request)
        }

        print("🟢 Mock Hue Bridge \"\(name)\" running on http://127.0.0.1:\(port)")
        print("   Rooms:  \(bridge.rooms.count)")
        print("   Lights: \(bridge.lights.count)")
        print("   Scenes: \(bridge.scenes.count)")
        print("")
        print("   Add in HueBar: enter 127.0.0.1:\(port) as manual IP")
        print("   Press Ctrl+C to stop")

        server.start()
        dispatchMain()
    }

    static func parseRooms(_ spec: String) -> [MockRoomDef] {
        spec.split(separator: ",").compactMap { part in
            let fields = part.split(separator: ":")
            guard fields.count >= 1 else { return nil }
            let name = String(fields[0])
            let archetype = fields.count >= 2 ? String(fields[1]) : name.lowercased().replacingOccurrences(of: " ", with: "_")
            let count = fields.count >= 3 ? Int(fields[2]) ?? 3 : 3
            return MockRoomDef(name: name, archetype: archetype, lightCount: count)
        }
    }

    static func printUsage() {
        print("""
        HueMockBridge — Mock Hue Bridge for testing HueBar

        Usage: HueMockBridge [options]

        Options:
          -p, --port <port>     Port to listen on (default: 8080)
          -n, --name <name>     Bridge name (default: "Mock Bridge")
          -r, --rooms <spec>    Room definitions (default: built-in set)
          -h, --help            Show this help

        Room spec format: "Name:archetype:lights,Name:archetype:lights"
          Example: "Kitchen:kitchen:3,Bedroom:bedroom:2"

        Examples:
          HueMockBridge --port 8080 --name "Upstairs"
          HueMockBridge -p 8081 -n "Garage" -r "Workshop:garage:4,Storage:storage:1"

        Run multiple instances on different ports to test multi-bridge.
        """)
    }
}
