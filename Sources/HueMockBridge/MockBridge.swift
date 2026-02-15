import Foundation

/// Room definition for configuring a mock bridge.
struct MockRoomDef: Sendable {
    let name: String
    let archetype: String
    let lightCount: Int

    static let defaults: [MockRoomDef] = [
        MockRoomDef(name: "Living Room", archetype: "living_room", lightCount: 4),
        MockRoomDef(name: "Bedroom", archetype: "bedroom", lightCount: 2),
        MockRoomDef(name: "Kitchen", archetype: "kitchen", lightCount: 3),
        MockRoomDef(name: "Office", archetype: "office", lightCount: 2),
    ]
}

/// In-memory state for a mock Hue bridge, generating realistic rooms/lights/scenes.
final class MockBridge: @unchecked Sendable {
    let bridgeName: String
    private let lock = NSLock()

    // State
    private(set) var rooms: [[String: Any]] = []
    private(set) var zones: [[String: Any]] = []
    private(set) var groupedLights: [[String: Any]] = []
    private(set) var lights: [[String: Any]] = []
    private(set) var scenes: [[String: Any]] = []

    // Indexed state for mutation
    private var lightStates: [String: (on: Bool, brightness: Double, mirek: Int)] = [:]
    private var groupedLightStates: [String: (on: Bool, brightness: Double, mirek: Int)] = [:]

    init(name: String, rooms roomDefs: [MockRoomDef] = MockRoomDef.defaults) {
        self.bridgeName = name
        generateState(roomDefs: roomDefs)
    }

    // MARK: - Logging

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func logRequest(_ request: HTTPRequest) {
        let ts = Self.timeFormatter.string(from: Date())
        var line = "[\(ts)] [\(bridgeName)] \(request.method) \(request.path)"
        if let body = request.body, !body.isEmpty {
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let compact = try? JSONSerialization.data(withJSONObject: json),
               let str = String(data: compact, encoding: .utf8) {
                line += " \(str)"
            } else {
                line += " \(body)"
            }
        }
        print(line)
    }

    // MARK: - Route Handling

    func handleRequest(_ request: HTTPRequest) -> HTTPResponse {
        logRequest(request)
        let path = request.path

        // Auth endpoint
        if path == "/api" && request.method == "POST" {
            return handleAuth()
        }

        // SSE event stream
        if path == "/eventstream/clip/v2" {
            return .sse()
        }

        // CLIP v2 resource endpoints
        let prefix = "/clip/v2/resource/"
        guard path.hasPrefix(prefix) else {
            return .json(["errors": [["description": "not found"]], "data": []], statusCode: 404)
        }

        let resource = String(path.dropFirst(prefix.count))

        if request.method == "GET" {
            return handleGet(resource: resource)
        } else if request.method == "PUT" {
            return handlePut(resource: resource, body: request.body)
        }

        return .json(["errors": [["description": "method not allowed"]], "data": []], statusCode: 405)
    }

    // MARK: - GET

    private func handleGet(resource: String) -> HTTPResponse {
        lock.lock()
        defer { lock.unlock() }

        let data: [[String: Any]]
        switch resource {
        case "room": data = rooms
        case "zone": data = zones
        case "grouped_light": data = groupedLights
        case "scene": data = scenes
        case "light": data = lights
        default: return .json(["errors": [["description": "unknown resource"]], "data": []])
        }
        return .json(["errors": [], "data": data])
    }

    // MARK: - PUT

    private func handlePut(resource: String, body: String?) -> HTTPResponse {
        guard let body, let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        else {
            return .json(["errors": [["description": "invalid body"]], "data": []])
        }

        let parts = resource.split(separator: "/")
        guard parts.count == 2 else {
            return .json(["errors": [["description": "invalid path"]], "data": []])
        }

        let resourceType = String(parts[0])
        let resourceId = String(parts[1])

        lock.lock()
        defer { lock.unlock() }

        switch resourceType {
        case "grouped_light":
            applyGroupedLightUpdate(id: resourceId, json: json)
        case "light":
            applyLightUpdate(id: resourceId, json: json)
        case "scene":
            applySceneRecall(id: resourceId, json: json)
        default: break
        }

        return .json(["errors": [], "data": [["rid": resourceId, "rtype": resourceType]]])
    }

    // MARK: - Auth

    private func handleAuth() -> HTTPResponse {
        let key = UUID().uuidString.lowercased()
        return .json([
            ["success": ["username": key, "clientkey": UUID().uuidString.lowercased()]]
        ])
    }

    // MARK: - State Generation

    private func generateState(roomDefs: [MockRoomDef]) {

        let sceneDefs = ["Energize", "Relax", "Concentrate", "Nightlight", "Bright"]
        let lightArchetypes = ["sultan_bulb", "flood_bulb", "spot_bulb", "candle_bulb", "luster_bulb"]

        for roomDef in roomDefs {
            let roomId = UUID().uuidString.lowercased()
            let groupedLightId = UUID().uuidString.lowercased()

            // Create lights for this room
            var childLinks: [[String: String]] = []
            var roomLightIds: [String] = []
            for i in 0..<roomDef.lightCount {
                let lightId = UUID().uuidString.lowercased()
                let deviceId = UUID().uuidString.lowercased()
                let isOn = Bool.random()
                let brightness = Double.random(in: 30...100).rounded()
                let mirek = Int.random(in: 153...500)
                let archetype = lightArchetypes[i % lightArchetypes.count]

                let light: [String: Any] = [
                    "id": lightId,
                    "owner": ["rid": deviceId, "rtype": "device"],
                    "metadata": ["name": "\(roomDef.name) \(i + 1)", "archetype": archetype],
                    "on": ["on": isOn],
                    "dimming": ["brightness": brightness],
                    "color": ["xy": ["x": Double.random(in: 0.2...0.6), "y": Double.random(in: 0.2...0.5)]],
                    "color_temperature": ["mirek": mirek, "mirek_valid": true],
                ]
                lights.append(light)
                lightStates[lightId] = (isOn, brightness, mirek)
                childLinks.append(["rid": lightId, "rtype": "light"])
                roomLightIds.append(lightId)
            }

            // Create grouped light
            let anyOn = roomLightIds.contains { lightStates[$0]?.on ?? false }
            let avgBrightness = roomLightIds.compactMap { lightStates[$0]?.brightness }.reduce(0, +) / Double(max(roomLightIds.count, 1))
            let firstMirek = lightStates[roomLightIds[0]]?.mirek ?? 250

            let groupedLight: [String: Any] = [
                "id": groupedLightId,
                "on": ["on": anyOn],
                "dimming": ["brightness": avgBrightness.rounded()],
                "color_temperature": ["mirek": firstMirek],
            ]
            groupedLights.append(groupedLight)
            groupedLightStates[groupedLightId] = (anyOn, avgBrightness, firstMirek)

            // Create room
            let room: [String: Any] = [
                "id": roomId,
                "metadata": ["name": roomDef.name, "archetype": roomDef.archetype],
                "services": [["rid": groupedLightId, "rtype": "grouped_light"]],
                "children": childLinks,
            ]
            rooms.append(room)

            // Create scenes for this room
            for sceneName in sceneDefs.shuffled().prefix(3) {
                let sceneId = UUID().uuidString.lowercased()
                let palette: [String: Any] = [
                    "color": [
                        ["color": ["xy": ["x": Double.random(in: 0.2...0.6), "y": Double.random(in: 0.2...0.5)]],
                         "dimming": ["brightness": Double.random(in: 40...100).rounded()]],
                    ],
                    "dimming": [["brightness": Double.random(in: 40...100).rounded()]],
                    "color_temperature": [] as [[String: Any]],
                ]
                let scene: [String: Any] = [
                    "id": sceneId,
                    "type": "scene",
                    "metadata": ["name": sceneName],
                    "group": ["rid": roomId, "rtype": "room"],
                    "status": ["active": "inactive"],
                    "palette": palette,
                    "speed": 0.5,
                    "auto_dynamic": false,
                ]
                scenes.append(scene)
            }
        }

        // Add one zone spanning two rooms
        let zoneId = UUID().uuidString.lowercased()
        let zoneGroupId = UUID().uuidString.lowercased()
        let zoneGroupedLight: [String: Any] = [
            "id": zoneGroupId,
            "on": ["on": true],
            "dimming": ["brightness": 75.0],
            "color_temperature": ["mirek": 300],
        ]
        groupedLights.append(zoneGroupedLight)
        groupedLightStates[zoneGroupId] = (true, 75, 300)

        let zone: [String: Any] = [
            "id": zoneId,
            "metadata": ["name": "Downstairs", "archetype": "downstairs"],
            "services": [["rid": zoneGroupId, "rtype": "grouped_light"]],
            "children": rooms.prefix(2).flatMap { ($0["children"] as? [[String: String]]) ?? [] },
        ]
        zones.append(zone)
    }

    // MARK: - State Mutation

    private func applyGroupedLightUpdate(id: String, json: [String: Any]) {
        guard let index = groupedLights.firstIndex(where: { ($0["id"] as? String) == id }) else { return }

        if let onDict = json["on"] as? [String: Any], let on = onDict["on"] as? Bool {
            var gl = groupedLights[index]
            gl["on"] = ["on": on]
            groupedLights[index] = gl
            groupedLightStates[id]?.on = on
        }
        if let dimmingDict = json["dimming"] as? [String: Any], let brightness = dimmingDict["brightness"] as? Double {
            var gl = groupedLights[index]
            gl["dimming"] = ["brightness": brightness]
            groupedLights[index] = gl
            groupedLightStates[id]?.brightness = brightness
        }
    }

    private func applyLightUpdate(id: String, json: [String: Any]) {
        guard let index = lights.firstIndex(where: { ($0["id"] as? String) == id }) else { return }

        if let onDict = json["on"] as? [String: Any], let on = onDict["on"] as? Bool {
            var l = lights[index]
            l["on"] = ["on": on]
            lights[index] = l
            lightStates[id]?.on = on
        }
        if let dimmingDict = json["dimming"] as? [String: Any], let brightness = dimmingDict["brightness"] as? Double {
            var l = lights[index]
            l["dimming"] = ["brightness": brightness]
            lights[index] = l
            lightStates[id]?.brightness = brightness
        }
        if let ctDict = json["color_temperature"] as? [String: Any], let mirek = ctDict["mirek"] as? Int {
            var l = lights[index]
            l["color_temperature"] = ["mirek": mirek, "mirek_valid": true]
            lights[index] = l
            lightStates[id]?.mirek = mirek
        }
        if let colorDict = json["color"] as? [String: Any], let xy = colorDict["xy"] as? [String: Any] {
            var l = lights[index]
            l["color"] = ["xy": xy]
            lights[index] = l
        }
    }

    private func applySceneRecall(id: String, json: [String: Any]) {
        guard let _ = json["recall"] as? [String: Any] else { return }
        // Set this scene to active, deactivate others in same group
        guard let sceneIndex = scenes.firstIndex(where: { ($0["id"] as? String) == id }),
              let group = scenes[sceneIndex]["group"] as? [String: String],
              let groupRid = group["rid"]
        else { return }

        for i in scenes.indices {
            if let g = scenes[i]["group"] as? [String: String], g["rid"] == groupRid {
                scenes[i]["status"] = ["active": (i == sceneIndex) ? "static" : "inactive"]
            }
        }
    }
}
