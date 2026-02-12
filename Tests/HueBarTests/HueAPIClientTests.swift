import Foundation
import Testing
@testable import HueBar

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
private func makeClient() -> HueAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return HueAPIClient(bridgeIP: "192.168.1.100", applicationKey: "test-key", session: session)
}

@Suite(.serialized)
@MainActor
struct HueAPIClientTests {

    // MARK: - JSON helpers

    private let roomsJSON = """
    {"errors":[],"data":[
        {"id":"room-1","metadata":{"name":"Living Room","archetype":"living_room"},"services":[{"rid":"gl-1","rtype":"grouped_light"}],"children":[]},
        {"id":"room-2","metadata":{"name":"Bedroom","archetype":"bedroom"},"services":[{"rid":"gl-2","rtype":"grouped_light"}],"children":[]}
    ]}
    """

    private let zonesJSON = """
    {"errors":[],"data":[
        {"id":"zone-1","metadata":{"name":"Downstairs","archetype":"home"},"services":[{"rid":"gl-3","rtype":"grouped_light"}],"children":[]}
    ]}
    """

    private let groupedLightsJSON = """
    {"errors":[],"data":[
        {"id":"gl-1","on":{"on":true},"dimming":{"brightness":80.0}},
        {"id":"gl-2","on":{"on":false},"dimming":{"brightness":0.0}}
    ]}
    """

    // MARK: - Tests

    @Test func fetchRooms() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString.contains("/clip/v2/resource/room") == true)
            #expect(request.value(forHTTPHeaderField: "hue-application-key") == "test-key")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(self.roomsJSON.utf8))
        }

        let rooms = try await client.fetchRooms()
        #expect(rooms.count == 2)
        #expect(rooms[0].name == "Living Room")
        #expect(rooms[1].name == "Bedroom")
    }

    @Test func fetchZones() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString.contains("/clip/v2/resource/zone") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(self.zonesJSON.utf8))
        }

        let zones = try await client.fetchZones()
        #expect(zones.count == 1)
        #expect(zones[0].name == "Downstairs")
    }

    @Test func fetchGroupedLights() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(self.groupedLightsJSON.utf8))
        }

        let lights = try await client.fetchGroupedLights()
        #expect(lights.count == 2)
        #expect(lights[0].isOn == true)
        #expect(lights[0].brightness == 80.0)
        #expect(lights[1].isOn == false)
    }

    @Test func fetchAll() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.absoluteString ?? ""
            let json: String
            if path.contains("/resource/room") {
                json = self.roomsJSON
            } else if path.contains("/resource/zone") {
                json = self.zonesJSON
            } else if path.contains("/resource/grouped_light") {
                json = self.groupedLightsJSON
            } else {
                json = #"{"errors":[],"data":[]}"#
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        await client.fetchAll()
        #expect(client.rooms.count == 2)
        #expect(client.zones.count == 1)
        #expect(client.groupedLights.count == 2)
        #expect(client.lastError == nil)
    }

    @Test func toggleGroupedLightOptimisticUpdate() async throws {
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000001"
        client.groupedLights = [
            GroupedLight(id: validId, on: OnState(on: true), dimming: DimmingState(brightness: 80.0)),
        ]

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PUT")
            // URLSession may move httpBody to httpBodyStream
            var bodyData = request.httpBody
            if bodyData == nil, let stream = request.httpBodyStream {
                stream.open()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
                defer { buffer.deallocate(); stream.close() }
                let read = stream.read(buffer, maxLength: 1024)
                if read > 0 { bodyData = Data(bytes: buffer, count: read) }
            }
            if let bodyData,
               let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let onDict = body["on"] as? [String: Bool] {
                #expect(onDict["on"] == false)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await client.toggleGroupedLight(id: validId, on: false)
        #expect(client.groupedLights.first?.isOn == false)
    }

    @Test func fetchRoomsHTTPError() async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await #expect(throws: HueAPIError.self) {
            _ = try await client.fetchRooms()
        }
    }

    @Test func fetchRoomsBridgeError() async throws {
        let client = makeClient()
        let json = #"{"errors":[{"description":"unauthorized user"}],"data":[]}"#
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        await #expect(throws: HueAPIError.self) {
            _ = try await client.fetchRooms()
        }
    }

    @Test func toggleInvalidResourceIdRejected() async {
        let client = makeClient()
        await #expect(throws: HueAPIError.self) {
            try await client.toggleGroupedLight(id: "../../../evil", on: true)
        }
    }

    @Test func groupedLightLookup() {
        let client = makeClient()
        client.groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: true), dimming: nil),
            GroupedLight(id: "gl-2", on: OnState(on: false), dimming: nil),
        ]

        let found = client.groupedLight(for: "gl-2")
        #expect(found?.id == "gl-2")
        #expect(found?.isOn == false)

        #expect(client.groupedLight(for: "unknown") == nil)
        #expect(client.groupedLight(for: nil) == nil)
    }

    @Test func scenesFilteredByGroup() {
        let client = makeClient()
        client.scenes = [
            HueScene(id: "s1", metadata: HueSceneMetadata(name: "Relax"), group: ResourceLink(rid: "room-1", rtype: "room"), status: nil, palette: nil),
            HueScene(id: "s2", metadata: HueSceneMetadata(name: "Energize"), group: ResourceLink(rid: "room-1", rtype: "room"), status: nil, palette: nil),
            HueScene(id: "s3", metadata: HueSceneMetadata(name: "Nightlight"), group: ResourceLink(rid: "room-2", rtype: "room"), status: nil, palette: nil),
        ]

        let room1Scenes = client.scenes(for: "room-1")
        #expect(room1Scenes.count == 2)
        #expect(room1Scenes[0].name == "Relax")
        #expect(room1Scenes[1].name == "Energize")

        let room2Scenes = client.scenes(for: "room-2")
        #expect(room2Scenes.count == 1)
        #expect(room2Scenes[0].name == "Nightlight")

        let noScenes = client.scenes(for: "unknown")
        #expect(noScenes.isEmpty)

        let nilScenes = client.scenes(for: nil)
        #expect(nilScenes.isEmpty)
    }

    @Test func setBrightnessInvalidIdRejected() async {
        let client = makeClient()
        await #expect(throws: HueAPIError.self) {
            try await client.setBrightness(groupedLightId: "../../../evil", brightness: 50)
        }
    }

    @Test func lightsFilteredByRoom() {
        let client = makeClient()
        let room = Room(
            id: "room-1",
            metadata: RoomMetadata(name: "Living Room", archetype: "living_room"),
            services: [ResourceLink(rid: "gl-1", rtype: "grouped_light")],
            children: [
                ResourceLink(rid: "device-A", rtype: "device"),
                ResourceLink(rid: "device-B", rtype: "device"),
            ]
        )
        client.lights = [
            makeLight(id: "l1", name: "Lamp", ownerRid: "device-A"),
            makeLight(id: "l2", name: "Ceiling", ownerRid: "device-B"),
            makeLight(id: "l3", name: "Other Room", ownerRid: "device-C"),
        ]

        let roomLights = client.lights(forRoom: room)
        #expect(roomLights.count == 2)
        #expect(roomLights.map(\.name).contains("Lamp"))
        #expect(roomLights.map(\.name).contains("Ceiling"))
    }

    @Test func lightsFilteredByZone() {
        let client = makeClient()
        let zone = Zone(
            id: "zone-1",
            metadata: ZoneMetadata(name: "Downstairs", archetype: "home"),
            services: [ResourceLink(rid: "gl-2", rtype: "grouped_light")],
            children: [
                ResourceLink(rid: "l1", rtype: "light"),
                ResourceLink(rid: "l3", rtype: "light"),
            ]
        )
        client.lights = [
            makeLight(id: "l1", name: "Lamp", ownerRid: "device-A"),
            makeLight(id: "l2", name: "Ceiling", ownerRid: "device-B"),
            makeLight(id: "l3", name: "Floor", ownerRid: "device-C"),
        ]

        let zoneLights = client.lights(forZone: zone)
        #expect(zoneLights.count == 2)
        #expect(zoneLights.map(\.name).contains("Lamp"))
        #expect(zoneLights.map(\.name).contains("Floor"))
    }

    @Test func toggleLightInvalidIdRejected() async {
        let client = makeClient()
        await #expect(throws: HueAPIError.self) {
            try await client.toggleLight(id: "../evil", on: true)
        }
    }

    private func makeLight(id: String, name: String, ownerRid: String) -> HueLight {
        HueLight(
            id: id,
            owner: ResourceLink(rid: ownerRid, rtype: "device"),
            metadata: LightMetadata(name: name, archetype: "classic_bulb"),
            on: OnState(on: true),
            dimming: DimmingState(brightness: 50),
            color: nil,
            color_temperature: nil
        )
    }
}
