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

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
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

    @Test func controlFailuresAreLoggedWithoutSecrets() async throws {
        let client = makeClient()
        var messages: [String] = []
        client.failureLogHandler = { messages.append($0) }
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet, userInfo: [
                NSLocalizedDescriptionKey: "test-key 192.168.1.100 sensitive transport detail",
            ])
        }

        await #expect(throws: URLError.self) {
            try await client.setSceneSpeed(id: "00000000-0000-0000-0000-000000000097", speed: 0.5)
        }
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data("test-key sensitive response body".utf8))
        }
        await #expect(throws: HueAPIError.self) {
            try await client.setSceneSpeed(id: "00000000-0000-0000-0000-000000000097", speed: 0.5)
        }
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"errors":[{"description":"test-key sensitive bridge detail"}],"data":[]}"#.utf8))
        }
        await #expect(throws: HueAPIError.self) {
            try await client.setSceneSpeed(id: "00000000-0000-0000-0000-000000000097", speed: 0.5)
        }
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("test-key invalid JSON".utf8))
        }
        await #expect(throws: DecodingError.self) {
            try await client.setSceneSpeed(id: "00000000-0000-0000-0000-000000000097", speed: 0.5)
        }

        let failures = messages.filter { $0.contains("PUT scene") }
        #expect(failures.count == 4)
        #expect(failures.allSatisfy { $0.contains("speed") })
        #expect(failures.contains { $0.contains("-1009") })
        #expect(failures.contains { $0.contains("HTTP 503") })
        #expect(failures.contains { $0.contains("bridge API") })
        #expect(failures.contains { $0.contains("decode") })
        #expect(!messages.contains {
            $0.contains("test-key") || $0.contains("192.168.1.100") || $0.contains("00000000-")
        })
    }

    @Test(arguments: ["bridge", "transport", "decode"])
    func groupColorReconciliationLogsOnlySafeDiagnostics(failure: String) async throws {
        let client = makeClient()
        var messages: [String] = []
        client.failureLogHandler = { messages.append($0) }
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "PUT" { throw URLError(.networkConnectionLost) }
            if failure == "transport" {
                throw URLError(.cannotConnectToHost, userInfo: [
                    NSLocalizedDescriptionKey: "test-key sensitive transport detail",
                ])
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = failure == "bridge"
                ? #"{"errors":[{"description":"test-key sensitive bridge detail"}],"data":[]}"#
                : "test-key invalid JSON"
            return (response, Data(json.utf8))
        }

        await #expect(throws: URLError.self) {
            try await client.setGroupedLightColor(
                id: "00000000-0000-0000-0000-000000000097",
                xy: CIEXYColor(x: 0.3, y: 0.4), lightIds: []
            )
        }

        let reconciliation = messages.filter { $0.contains("reconcile group color") }
        #expect(reconciliation.count == 1)
        let expected = failure == "bridge" ? "bridge API" : failure == "transport" ? "-1004" : "decode"
        #expect(reconciliation.allSatisfy { $0.contains(expected) })
        #expect(messages.allSatisfy { !$0.contains("test-key") && !$0.contains("sensitive") })
    }

    @Test(arguments: [
        "light-toggle", "light-brightness", "light-color", "light-temperature",
        "group-toggle", "group-brightness", "group-color", "group-temperature",
        "scene-recall", "scene-speed",
    ])
    func controlBridgeErrorsArePropagated(operation: String) async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = request.httpMethod == "PUT"
                ? #"{"errors":[{"description":"control rejected"}],"data":[]}"#
                : #"{"errors":[],"data":[]}"#
            return (response, Data(json.utf8))
        }

        do {
            try await performControl(operation, client: client)
            Issue.record("Expected bridge control error for \(operation)")
        } catch HueAPIError.bridgeError(let description) {
            #expect(description == "control rejected")
        }
    }

    @Test(arguments: [
        "light-toggle", "light-brightness", "light-color", "light-temperature",
        "group-toggle", "group-brightness", "group-color", "group-temperature",
        "scene-recall", "scene-speed",
    ], ["transport", "http", "malformed", "empty-success", "envelope-success"])
    func controlResponseHandling(operation: String, responseKind: String) async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "PUT", responseKind == "transport" {
                throw URLError(.networkConnectionLost)
            }
            let isControl = request.httpMethod == "PUT"
            let status = isControl && responseKind == "http" ? 500 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            let data: Data
            if isControl && responseKind == "malformed" {
                data = Data("invalid JSON".utf8)
            } else if isControl && responseKind == "empty-success" {
                data = Data()
            } else {
                data = Data(#"{"errors":[],"data":[]}"#.utf8)
            }
            return (response, data)
        }

        switch responseKind {
        case "transport":
            do {
                try await performControl(operation, client: client)
                Issue.record("Expected transport error")
            } catch let error as URLError {
                #expect(error.code == .networkConnectionLost)
            }
        case "http":
            do {
                try await performControl(operation, client: client)
                Issue.record("Expected HTTP error")
            } catch HueAPIError.invalidResponse {}
        case "malformed":
            await #expect(throws: DecodingError.self) {
                try await performControl(operation, client: client)
            }
        case "empty-success", "envelope-success":
            try await performControl(operation, client: client)
        default: Issue.record("Unknown response kind")
        }
    }

    @Test(arguments: ["transport", "http", "bridge"])
    func sceneSpeedFailureRestoresOptimisticState(failure: String) async throws {
        let client = makeClient()
        let id = "00000000-0000-0000-0000-000000000097"
        client.scenes = [makeScene(id: id, name: "Scene", groupId: "room-1", status: .inactive)]
        client.scenes[0].speed = 0.2
        MockURLProtocol.requestHandler = { request in
            if failure == "transport" { throw URLError(.networkConnectionLost) }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: failure == "http" ? 500 : 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"errors":[{"description":"rejected"}],"data":[]}"#.utf8))
        }

        await #expect(throws: (any Error).self) {
            try await client.setSceneSpeed(id: id, speed: 0.8)
        }
        #expect(client.scenes[0].speed == 0.2)
    }

    @Test(arguments: [
        "light-toggle", "light-brightness", "light-color", "light-temperature",
        "group-toggle", "group-brightness", "group-color", "group-temperature",
    ])
    func failedReconciliationPreservesControlError(operation: String) async throws {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "PUT" {
                throw URLError(.networkConnectionLost)
            }
            throw URLError(.cannotConnectToHost)
        }

        do {
            try await performControl(operation, client: client)
            Issue.record("Expected original transport error")
        } catch let error as URLError {
            #expect(error.code == .networkConnectionLost)
        }
    }

    private func performControl(_ operation: String, client: HueAPIClient) async throws {
        let id = "00000000-0000-0000-0000-000000000097"
        switch operation {
        case "light-toggle": try await client.toggleLight(id: id, on: false)
        case "light-brightness": try await client.setLightBrightness(id: id, brightness: 50)
        case "light-color": try await client.setLightColor(id: id, xy: CIEXYColor(x: 0.3, y: 0.4))
        case "light-temperature": try await client.setLightColorTemperature(id: id, mirek: 300)
        case "group-toggle": try await client.toggleGroupedLight(id: id, on: false)
        case "group-brightness": try await client.setBrightness(groupedLightId: id, brightness: 50)
        case "group-color": try await client.setGroupedLightColor(id: id, xy: CIEXYColor(x: 0.3, y: 0.4), lightIds: [])
        case "group-temperature": try await client.setGroupedLightColorTemperature(id: id, mirek: 300)
        case "scene-recall": try await client.recallScene(id: id)
        case "scene-speed": try await client.setSceneSpeed(id: id, speed: 0.5)
        default: Issue.record("Unknown control operation \(operation)")
        }
    }

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

    @Test func eventStreamReconnectRefreshesBridgeState() async throws {
        // Arrange
        let context = createEventStreamReconnectContext()
        await context.client.fetchAll()
        #expect(context.client.groupedLights.first?.isOn == true)

        // Act
        context.client.startEventStream()
        defer { context.client.stopEventStream() }
        let didRefresh = await waitUntil {
            context.client.groupedLights.first?.isOn == false
        }

        // Assert
        #expect(didRefresh)
        #expect(context.groupedLightRequestCount() >= 2)
        #expect(context.eventStreamRequestCount() >= 2)
    }

    @Test func lightEventUpdatesContainingRoomGroupedLightState() {
        // Arrange
        let client = makeClient()
        let groupedLightId = "grouped-office"
        let lightId = "office-light-1"
        client.rooms = [
            Room(
                id: "office-room",
                metadata: GroupMetadata(name: "Office", archetype: "office"),
                services: [ResourceLink(rid: groupedLightId, rtype: "grouped_light")],
                children: [ResourceLink(rid: "office-device-1", rtype: "device")]
            ),
        ]
        client.groupedLights = [
            GroupedLight(id: groupedLightId, on: OnState(on: true), dimming: DimmingState(brightness: 80), colorTemperature: nil),
        ]
        client.lights = [
            makeLight(id: lightId, name: "Office Desk", ownerRid: "office-device-1"),
        ]

        // Act
        client.applyEvents([
            makeUpdateEvent(resources: [
                HueEventResource(
                    id: lightId,
                    type: "light",
                    on: OnState(on: false),
                    dimming: nil,
                    color: nil,
                    colorTemperature: nil,
                    status: nil,
                    metadata: nil,
                    speed: nil
                ),
            ]),
        ])

        // Assert
        #expect(client.lights.first?.isOn == false)
        #expect(client.groupedLight(for: groupedLightId)?.isOn == false)
    }

    @Test func roomGroupedLightStaysOnUntilLastMemberLightTurnsOff() {
        // Arrange
        let client = makeClient()
        let groupedLightId = "00000000-0000-0000-0000-0000000000a1"
        configureOfficeRoom(client, groupedLightId: groupedLightId, lightIds: ["office-light-1", "office-light-2"])

        // Act & Assert
        client.applyEvents([makeUpdateEvent(resource: makeLightEventResource(id: "office-light-1", on: false))])
        #expect(client.groupedLight(for: groupedLightId)?.isOn == true)

        client.applyEvents([makeUpdateEvent(resource: makeLightEventResource(id: "office-light-2", on: false))])
        #expect(client.groupedLight(for: groupedLightId)?.isOn == false)
    }

    @Test func lightEventWithoutOnStateDoesNotRecomputeRoomGroupedLightState() async throws {
        // Arrange
        let client = makeClient()
        let groupedLightId = "00000000-0000-0000-0000-0000000000a2"
        configureOfficeRoom(client, groupedLightId: groupedLightId, lightIds: ["office-light-1"])
        client.groupedLights[0].on = OnState(on: false)

        // Act
        client.applyEvents([makeUpdateEvent(resource: makeLightEventResource(id: "office-light-1", brightness: 30))])

        // Assert
        #expect(client.lights.first?.dimming?.brightness == 30)
        #expect(client.groupedLight(for: groupedLightId)?.isOn == false)
    }

    @Test func memberLightEventsDoNotRevertPendingRoomToggle() async throws {
        // Arrange
        let client = makeClient()
        let groupedLightId = "00000000-0000-0000-0000-0000000000a3"
        configureOfficeRoom(client, groupedLightId: groupedLightId, lightIds: ["office-light-1", "office-light-2"])
        stubSuccessfulResponses()
        try await client.toggleGroupedLight(id: groupedLightId, on: false)

        // Act & Assert: the first light reports off while the second is still cached as on
        client.applyEvents([makeUpdateEvent(resource: makeLightEventResource(id: "office-light-1", on: false))])
        #expect(client.groupedLight(for: groupedLightId)?.isOn == false)

        client.applyEvents([makeUpdateEvent(resource: makeLightEventResource(id: "office-light-2", on: false))])
        #expect(client.groupedLight(for: groupedLightId)?.isOn == false)

        // The bridge's own grouped_light event confirms the toggle and ends the protection
        client.applyEvents([makeUpdateEvent(resource: makeGroupedLightEventResource(id: groupedLightId, on: false))])
        client.applyEvents([makeUpdateEvent(resource: makeLightEventResource(id: "office-light-1", on: true))])
        #expect(client.groupedLight(for: groupedLightId)?.isOn == true)
    }

    @Test func memberLightEventsDoNotRevertRoomToggledOffThenOnAgain() async throws {
        // Arrange
        let client = makeClient()
        let groupedLightId = "00000000-0000-0000-0000-0000000000a4"
        configureOfficeRoom(client, groupedLightId: groupedLightId, lightIds: ["office-light-1", "office-light-2"])
        stubSuccessfulResponses()
        try await client.toggleGroupedLight(id: groupedLightId, on: false)
        try await client.toggleGroupedLight(id: groupedLightId, on: true)

        // Act: events from the first (off) command arrive after the second toggle
        client.applyEvents([makeUpdateEvent(resource: makeLightEventResource(id: "office-light-1", on: false))])
        client.applyEvents([makeUpdateEvent(resource: makeLightEventResource(id: "office-light-2", on: false))])
        client.applyEvents([makeUpdateEvent(resource: makeGroupedLightEventResource(id: groupedLightId, on: false))])

        // Assert
        #expect(client.groupedLight(for: groupedLightId)?.isOn == true)
    }

    @Test func toggleGroupedLightOptimisticUpdate() async throws {
        // Arrange
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000001"
        client.groupedLights = [
            GroupedLight(id: validId, on: OnState(on: true), dimming: DimmingState(brightness: 80.0), colorTemperature: nil),
        ]
        let observedStateBeforeResponse = LockedValue<Bool?>(nil)

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
            let stateWasRead = DispatchSemaphore(value: 0)
            Task { @MainActor in
                observedStateBeforeResponse.set(client.groupedLights.first?.isOn)
                stateWasRead.signal()
            }
            #expect(stateWasRead.wait(timeout: .now() + 2) == .success)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Act
        try await client.toggleGroupedLight(id: validId, on: false)
        #expect(observedStateBeforeResponse.get() == false)
        #expect(client.groupedLights.first?.isOn == false)
        #expect(client.groupedLights.first?.brightness == 80)
    }

    @Test func toggleGroupedLightOnPreservesOptimisticBrightness() async throws {
        // Arrange
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000002"
        client.groupedLights = [
            GroupedLight(id: validId, on: OnState(on: false), dimming: DimmingState(brightness: 35.0), colorTemperature: nil),
        ]

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PUT")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Act
        try await client.toggleGroupedLight(id: validId, on: true)

        // Assert
        #expect(client.groupedLights.first?.isOn == true)
        #expect(client.groupedLights.first?.brightness == 35)
    }

    @Test func toggleGroupedLightOffOptimisticallyUpdatesRoomLights() async throws {
        // Arrange
        let client = makeClient()
        let groupedLightId = "00000000-0000-0000-0000-000000000003"
        client.rooms = [
            Room(
                id: "office-room",
                metadata: GroupMetadata(name: "Office", archetype: "office"),
                services: [ResourceLink(rid: groupedLightId, rtype: "grouped_light")],
                children: [
                    ResourceLink(rid: "office-device-1", rtype: "device"),
                    ResourceLink(rid: "office-device-2", rtype: "device"),
                ]
            ),
        ]
        client.groupedLights = [
            GroupedLight(id: groupedLightId, on: OnState(on: true), dimming: DimmingState(brightness: 80.0), colorTemperature: nil),
        ]
        client.lights = [
            makeLight(id: "office-light-1", name: "Office Desk", ownerRid: "office-device-1"),
            makeLight(id: "office-light-2", name: "Office Ceiling", ownerRid: "office-device-2"),
            makeLight(id: "kitchen-light-1", name: "Kitchen", ownerRid: "kitchen-device-1"),
        ]

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PUT")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Act
        try await client.toggleGroupedLight(id: groupedLightId, on: false)

        // Assert
        let officeLights = client.lights.filter { $0.id.hasPrefix("office-light") }
        #expect(officeLights.allSatisfy { $0.isOn == false })
        #expect(officeLights.allSatisfy { $0.brightness == 50 })
        #expect(client.lights.first(where: { $0.id == "kitchen-light-1" })?.isOn == true)
        #expect(client.lights.first(where: { $0.id == "kitchen-light-1" })?.brightness == 50)
    }

    @Test func toggleGroupedLightOnOptimisticallyUpdatesRoomLights() async throws {
        // Arrange
        let client = makeClient()
        let groupedLightId = "00000000-0000-0000-0000-000000000004"
        client.rooms = [
            Room(
                id: "office-room",
                metadata: GroupMetadata(name: "Office", archetype: "office"),
                services: [ResourceLink(rid: groupedLightId, rtype: "grouped_light")],
                children: [
                    ResourceLink(rid: "office-device-1", rtype: "device"),
                    ResourceLink(rid: "office-device-2", rtype: "device"),
                ]
            ),
        ]
        client.groupedLights = [
            GroupedLight(id: groupedLightId, on: OnState(on: false), dimming: DimmingState(brightness: 35.0), colorTemperature: nil),
        ]
        client.lights = [
            makeLight(id: "office-light-1", name: "Office Desk", ownerRid: "office-device-1"),
            makeLight(id: "office-light-2", name: "Office Ceiling", ownerRid: "office-device-2"),
            makeLight(id: "kitchen-light-1", name: "Kitchen", ownerRid: "kitchen-device-1"),
        ]
        client.lights[0].on = OnState(on: false)
        client.lights[0].dimming = DimmingState(brightness: 25)
        client.lights[1].on = OnState(on: false)
        client.lights[1].dimming = DimmingState(brightness: 45)
        client.lights[2].on = OnState(on: false)

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PUT")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Act
        try await client.toggleGroupedLight(id: groupedLightId, on: true)

        // Assert
        let officeLights = client.lights.filter { $0.id.hasPrefix("office-light") }
        #expect(officeLights.allSatisfy { $0.isOn == true })
        #expect(client.lights.first(where: { $0.id == "office-light-1" })?.brightness == 25)
        #expect(client.lights.first(where: { $0.id == "office-light-2" })?.brightness == 45)
        #expect(client.lights.first(where: { $0.id == "kitchen-light-1" })?.isOn == false)
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
            GroupedLight(id: "gl-1", on: OnState(on: true), dimming: nil, colorTemperature: nil),
            GroupedLight(id: "gl-2", on: OnState(on: false), dimming: nil, colorTemperature: nil),
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
            HueScene(id: "s1", type: "scene", metadata: HueSceneMetadata(name: "Relax", image: nil), group: ResourceLink(rid: "room-1", rtype: "room"), status: nil, palette: nil, speed: nil, autoDynamic: nil),
            HueScene(id: "s2", type: "scene", metadata: HueSceneMetadata(name: "Energize", image: nil), group: ResourceLink(rid: "room-1", rtype: "room"), status: nil, palette: nil, speed: nil, autoDynamic: nil),
            HueScene(id: "s3", type: "scene", metadata: HueSceneMetadata(name: "Nightlight", image: nil), group: ResourceLink(rid: "room-2", rtype: "room"), status: nil, palette: nil, speed: nil, autoDynamic: nil),
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

    @Test func pendingGroupedBrightnessIgnoresStaleSSEUntilMatchingEvent() async throws {
        // Arrange
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000012"
        client.groupedLights = [
            GroupedLight(id: validId, on: OnState(on: true), dimming: DimmingState(brightness: 12.0), colorTemperature: nil),
        ]
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PUT")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Act
        try await client.setBrightness(groupedLightId: validId, brightness: 40.0)
        client.applyEvents([
            makeUpdateEvent(
                resource: HueEventResource(
                    id: validId,
                    type: "grouped_light",
                    on: nil,
                    dimming: DimmingState(brightness: 12.0),
                    color: nil,
                    colorTemperature: nil,
                    status: nil,
                    metadata: nil,
                    speed: nil
                )
            ),
        ])

        // Assert
        #expect(client.groupedLights.first?.brightness == 40.0)

        // Act
        client.applyEvents([
            makeUpdateEvent(
                resource: HueEventResource(
                    id: validId,
                    type: "grouped_light",
                    on: nil,
                    dimming: DimmingState(brightness: 40.0),
                    color: nil,
                    colorTemperature: nil,
                    status: nil,
                    metadata: nil,
                    speed: nil
                )
            ),
        ])
        client.applyEvents([
            makeUpdateEvent(
                resource: HueEventResource(
                    id: validId,
                    type: "grouped_light",
                    on: nil,
                    dimming: DimmingState(brightness: 65.0),
                    color: nil,
                    colorTemperature: nil,
                    status: nil,
                    metadata: nil,
                    speed: nil
                )
            ),
        ])

        // Assert
        #expect(client.groupedLights.first?.brightness == 65.0)
    }

    @Test func previewGroupedBrightnessProtectsDebouncedChangeFromStaleSSE() {
        // Arrange
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000013"
        client.groupedLights = [
            GroupedLight(id: validId, on: OnState(on: true), dimming: DimmingState(brightness: 12.0), colorTemperature: nil),
        ]

        // Act
        client.previewBrightness(groupedLightId: validId, brightness: 40.0)
        client.applyEvents([
            makeUpdateEvent(
                resource: HueEventResource(
                    id: validId,
                    type: "grouped_light",
                    on: nil,
                    dimming: DimmingState(brightness: 12.0),
                    color: nil,
                    colorTemperature: nil,
                    status: nil,
                    metadata: nil,
                    speed: nil
                )
            ),
        ])

        // Assert
        #expect(client.groupedLights.first?.brightness == 40.0)
    }

    @Test func lightsFilteredByRoom() {
        let client = makeClient()
        let room = Room(
            id: "room-1",
            metadata: GroupMetadata(name: "Living Room", archetype: "living_room"),
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
            metadata: GroupMetadata(name: "Downstairs", archetype: "home"),
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

    // MARK: - Light control tests

    @Test func toggleLightOptimisticUpdate() async throws {
        // Arrange
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000001"
        client.lights = [makeLight(id: validId, name: "Lamp", ownerRid: "device-A")]
        let observedStateBeforeResponse = LockedValue<Bool?>(nil)

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.absoluteString.contains("/clip/v2/resource/light/\(validId)") == true)
            let stateWasRead = DispatchSemaphore(value: 0)
            Task { @MainActor in
                observedStateBeforeResponse.set(client.lights.first?.isOn)
                stateWasRead.signal()
            }
            #expect(stateWasRead.wait(timeout: .now() + 2) == .success)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Act
        try await client.toggleLight(id: validId, on: false)
        #expect(observedStateBeforeResponse.get() == false)
        #expect(client.lights.first?.isOn == false)
        #expect(client.lights.first?.brightness == 50)
    }

    @Test func toggleLightOnPreservesOptimisticBrightness() async throws {
        // Arrange
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000002"
        client.lights = [makeLight(id: validId, name: "Lamp", ownerRid: "device-A")]
        client.lights[0].on = OnState(on: false)
        client.lights[0].dimming = DimmingState(brightness: 35)

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.absoluteString.contains("/clip/v2/resource/light/\(validId)") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Act
        try await client.toggleLight(id: validId, on: true)

        // Assert
        #expect(client.lights.first?.isOn == true)
        #expect(client.lights.first?.brightness == 35)
    }

    @Test func toggleLightOffThenOnPreservesDimmingAndAcceptsBrightnessEvents() async throws {
        let client = makeClient()
        let id = "00000000-0000-0000-0000-000000000022"
        client.lights = [makeLight(id: id, name: "Lamp", ownerRid: "device-A")]
        stubSuccessfulResponses()

        try await client.toggleLight(id: id, on: false)
        #expect(client.lights[0].dimming?.brightness == 50)
        #expect(!client.lights[0].isOn)
        #expect(client.lights[0].displayBrightness == 0)
        try await client.toggleLight(id: id, on: true)
        #expect(client.lights[0].brightness == 50)
        #expect(client.lights[0].displayBrightness == 50)

        client.applyEvents([
            makeUpdateEvent(resource: HueEventResource(
                id: id, type: "light", on: OnState(on: false),
                dimming: DimmingState(brightness: 65), color: nil, colorTemperature: nil,
                status: nil, metadata: nil, speed: nil
            )),
        ])
        #expect(client.lights[0].isOn)
        #expect(client.lights[0].brightness == 65)
    }

    @Test(arguments: [false, true])
    func toggleGroupOffThenOnPreservesMemberDimmingAndAcceptsBrightnessEvents(isZone: Bool) async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000023"
        let memberId = "00000000-0000-0000-0000-000000000024"
        let services = [ResourceLink(rid: groupId, rtype: "grouped_light")]
        if isZone {
            client.zones = [Zone(
                id: "zone", metadata: GroupMetadata(name: "Zone", archetype: "home"),
                services: services, children: [ResourceLink(rid: memberId, rtype: "light")]
            )]
        } else {
            client.rooms = [Room(
                id: "room", metadata: GroupMetadata(name: "Room", archetype: "office"),
                services: services, children: [ResourceLink(rid: "device-A", rtype: "device")]
            )]
        }
        client.groupedLights = [
            GroupedLight(id: groupId, on: OnState(on: true), dimming: DimmingState(brightness: 80), colorTemperature: nil),
        ]
        client.lights = [
            makeLight(id: memberId, name: "Member", ownerRid: "device-A"),
            makeLight(id: "other-light", name: "Other", ownerRid: "device-B"),
        ]
        stubSuccessfulResponses()

        try await client.toggleGroupedLight(id: groupId, on: false)
        #expect(!client.groupedLights[0].isOn)
        #expect(!client.lights[0].isOn)
        #expect(client.groupedLights[0].dimming?.brightness == 80)
        #expect(client.lights[0].dimming?.brightness == 50)
        #expect(client.groupedLights[0].displayBrightness == 0)
        #expect(client.lights[0].displayBrightness == 0)
        #expect(client.lights[1].isOn)

        try await client.toggleGroupedLight(id: groupId, on: true)
        #expect(client.groupedLights[0].brightness == 80)
        #expect(client.lights[0].brightness == 50)
        #expect(client.groupedLights[0].displayBrightness == 80)
        #expect(client.lights[0].displayBrightness == 50)
        for (id, type) in [(groupId, "grouped_light"), (memberId, "light")] {
            client.applyEvents([
                makeUpdateEvent(resource: HueEventResource(
                    id: id, type: type, on: OnState(on: false),
                    dimming: DimmingState(brightness: 65), color: nil, colorTemperature: nil,
                    status: nil, metadata: nil, speed: nil
                )),
            ])
        }
        #expect(client.groupedLights[0].isOn)
        #expect(client.lights[0].isOn)
        #expect(client.groupedLights[0].brightness == 65)
        #expect(client.lights[0].brightness == 65)
        #expect(client.lights[1].brightness == 50)
    }

    @Test func togglesPreservePendingBrightnessProtection() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000025"
        let lightId = "00000000-0000-0000-0000-000000000026"
        configureOfficeRoom(client, groupedLightId: groupId, lightIds: [lightId])
        stubSuccessfulResponses()
        client.previewBrightness(groupedLightId: groupId, brightness: 70)
        client.previewLightBrightness(id: lightId, brightness: 40)

        try await client.toggleGroupedLight(id: groupId, on: false)
        try await client.toggleLight(id: lightId, on: true)
        try await client.toggleGroupedLight(id: groupId, on: true)
        for (id, type) in [(groupId, "grouped_light"), (lightId, "light")] {
            client.applyEvents([
                makeUpdateEvent(resource: HueEventResource(
                    id: id, type: type, on: nil,
                    dimming: DimmingState(brightness: 10), color: nil, colorTemperature: nil,
                    status: nil, metadata: nil, speed: nil
                )),
            ])
        }
        #expect(client.groupedLights[0].brightness == 70)
        #expect(client.lights[0].brightness == 40)
    }

    @Test func setLightBrightnessClamping() async throws {
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000002"
        client.lights = [makeLight(id: validId, name: "Lamp", ownerRid: "device-A")]

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Value above 100 should be clamped
        try await client.setLightBrightness(id: validId, brightness: 150.0)
        #expect(client.lights.first?.brightness == 100.0)

        // Value below 0 should be clamped
        try await client.setLightBrightness(id: validId, brightness: -10.0)
        #expect(client.lights.first?.brightness == 0.0)
    }

    @Test func setLightColorUpdatesState() async throws {
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000003"
        client.lights = [makeLight(id: validId, name: "Lamp", ownerRid: "device-A")]

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let xy = CIEXYColor(x: 0.3, y: 0.5)
        try await client.setLightColor(id: validId, xy: xy)
        #expect(client.lights.first?.color?.xy.x == 0.3)
        #expect(client.lights.first?.color?.xy.y == 0.5)
    }

    @Test func setGroupedLightColorSendsGroupRequestAndUpdatesLights() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000010"
        let lightA = "00000000-0000-0000-0000-000000000011"
        let lightB = "00000000-0000-0000-0000-000000000012"
        let other = "00000000-0000-0000-0000-000000000013"
        client.lights = [
            makeLight(id: lightA, name: "A", ownerRid: "device-A"),
            makeLight(id: lightB, name: "B", ownerRid: "device-B"),
            makeLight(id: other, name: "Other", ownerRid: "device-C"),
        ]

        let sentRequest = LockedValue<URLRequest?>(nil)
        MockURLProtocol.requestHandler = { request in
            sentRequest.set(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await client.setGroupedLightColor(id: groupId, xy: CIEXYColor(x: 0.3, y: 0.5), lightIds: [lightA, lightB])

        let request = try #require(sentRequest.get())
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/clip/v2/resource/grouped_light/\(groupId)")
        #expect(client.lights[0].color?.xy.x == 0.3)
        #expect(client.lights[1].color?.xy.y == 0.5)
        #expect(client.lights[2].color == nil)
    }

    @Test func setGroupedLightColorRevertsLightsOnFailure() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000014"
        let lightId = "00000000-0000-0000-0000-000000000015"
        client.lights = [makeLight(id: lightId, name: "Lamp", ownerRid: "device-A")]

        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "PUT" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"errors":[],"data":[{"id":"\(lightId)","owner":{"rid":"device-A","rtype":"device"},"metadata":{"name":"Lamp"},"on":{"on":true},"color":{"xy":{"x":0.1,"y":0.2}}}]}
            """
            return (response, Data(body.utf8))
        }

        await #expect(throws: HueAPIError.self) {
            try await client.setGroupedLightColor(id: groupId, xy: CIEXYColor(x: 0.3, y: 0.5), lightIds: [lightId])
        }
        #expect(client.lights.first?.color?.xy.x == 0.1)
    }

    @Test func groupColorTransportFailureRestoresPreviewAndAcceptsEvents() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000014"
        let lightId = "00000000-0000-0000-0000-000000000015"
        client.lights = [makeLight(id: lightId, name: "Lamp", ownerRid: "device-A")]
        client.lights[0].color = LightColor(xy: CIEXYColor(x: 0.1, y: 0.2))
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        client.previewGroupedLightColor(lightIds: [lightId], xy: CIEXYColor(x: 0.3, y: 0.5))
        await #expect(throws: URLError.self) {
            try await client.setGroupedLightColor(id: groupId, xy: CIEXYColor(x: 0.3, y: 0.5), lightIds: [lightId])
        }
        #expect(client.lights[0].color?.xy.x == 0.1)
        client.applyEvents([
            makeUpdateEvent(resource: HueEventResource(
                id: lightId, type: "light", on: nil, dimming: nil,
                color: HueEventColor(xy: CIEXYColor(x: 0.2, y: 0.3)),
                colorTemperature: nil, status: nil, metadata: nil, speed: nil
            )),
        ])
        #expect(client.lights[0].color?.xy.x == 0.2)
    }

    @Test func groupColorDebounceFlushesLatestPreviewOnDisappear() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000014"
        let lightId = "00000000-0000-0000-0000-000000000015"
        client.lights = [makeLight(id: lightId, name: "Lamp", ownerRid: "device-A")]
        let requests = LockedValue(0)
        MockURLProtocol.requestHandler = { request in
            requests.set(requests.get() + 1)
            #expect(request.url?.path == "/clip/v2/resource/grouped_light/\(groupId)")
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                let count = stream.read(&buffer, maxLength: buffer.count)
                try #require(count > 0)
                data = Data(buffer.prefix(count))
            }
            let body = try JSONDecoder().decode([String: [String: [String: Double]]].self, from: data)
            #expect(body["color"]?["xy"]?["x"] == 0.4)
            #expect(body["color"]?["xy"]?["y"] == 0.5)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let change = GroupColorChange()
        change.schedule(client: client, id: groupId, lightIds: [lightId], xy: CIEXYColor(x: 0.2, y: 0.3))
        change.schedule(client: client, id: groupId, lightIds: [lightId], xy: CIEXYColor(x: 0.4, y: 0.5))
        #expect(client.lights[0].color?.xy.x == 0.4)
        #expect(requests.get() == 0)
        await change.flush()?.value
        #expect(client.lights[0].color?.xy.x == 0.4)
        #expect(requests.get() == 1)
        #expect(change.flush() == nil)
        try await Task.sleep(for: .milliseconds(250))
        #expect(requests.get() == 1)
    }

    @Test func groupColorDebounceSendsWithoutDisappear() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000014"
        let lightId = "00000000-0000-0000-0000-000000000015"
        client.lights = [makeLight(id: lightId, name: "Lamp", ownerRid: "device-A")]
        let requests = LockedValue(0)
        MockURLProtocol.requestHandler = { request in
            requests.set(requests.get() + 1)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let change = GroupColorChange()
        change.schedule(client: client, id: groupId, lightIds: [lightId], xy: CIEXYColor(x: 0.4, y: 0.5))
        try await Task.sleep(for: .milliseconds(350))
        #expect(requests.get() == 1)
        #expect(client.lights[0].color?.xy.x == 0.4)
        #expect(change.flush() == nil)
    }

    @Test(arguments: ["transport", "http", "bridge", "encoding", "cancelled"])
    func groupColorErrorsReconcileAuthoritativeState(failure: String) async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000014"
        let lightId = "00000000-0000-0000-0000-000000000015"
        client.lights = [makeLight(id: lightId, name: "Lamp", ownerRid: "device-A")]
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "PUT" {
                if failure == "transport" { throw URLError(.networkConnectionLost) }
                if failure == "cancelled" { throw URLError(.cancelled) }
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: failure == "http" ? 500 : 200,
                    httpVersion: nil, headerFields: nil
                )!
                return (response, Data(#"{"errors":[{"description":"rejected"}],"data":[]}"#.utf8))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"errors":[],"data":[{"id":"\(lightId)","owner":{"rid":"device-A","rtype":"device"},"metadata":{"name":"Lamp"},"on":{"on":true},"color":{"xy":{"x":0.1,"y":0.2}}}]}
            """
            return (response, Data(body.utf8))
        }
        let xy = CIEXYColor(x: failure == "encoding" ? .nan : 0.3, y: 0.5)
        client.previewGroupedLightColor(lightIds: [lightId], xy: xy)
        await #expect(throws: (any Error).self) {
            try await client.setGroupedLightColor(id: groupId, xy: xy, lightIds: [lightId])
        }
        #expect(client.lights[0].color?.xy.x == 0.1)
    }

    @Test func groupColorOldFailureDoesNotOverwriteNewDrag() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000014"
        let lightId = "00000000-0000-0000-0000-000000000015"
        client.lights = [makeLight(id: lightId, name: "Lamp", ownerRid: "device-A")]
        let started = LockedValue(false)
        let release = DispatchSemaphore(value: 0)
        let requests = LockedValue(0)
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "PUT" {
                requests.set(requests.get() + 1)
                if requests.get() == 1 {
                    started.set(true)
                    #expect(release.wait(timeout: .now() + 3) == .success)
                    throw URLError(.networkConnectionLost)
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            throw URLError(.notConnectedToInternet)
        }
        let change = GroupColorChange()
        change.schedule(client: client, id: groupId, lightIds: [lightId], xy: CIEXYColor(x: 0.2, y: 0.3))
        let first = try #require(change.flush())
        defer { release.signal() }
        for _ in 0..<100 where !started.get() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(started.get())
        change.schedule(client: client, id: groupId, lightIds: [lightId], xy: CIEXYColor(x: 0.6, y: 0.3))
        release.signal()
        await first.value
        #expect(client.lights[0].color?.xy.x == 0.6)
        await change.flush()?.value
        #expect(requests.get() == 2)
        #expect(client.lights[0].color?.xy.x == 0.6)
    }

    @Test func groupColorFailureDoesNotOverwriteNewIndividualColor() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000014"
        let lightId = "00000000-0000-0000-0000-000000000015"
        client.lights = [makeLight(id: lightId, name: "Lamp", ownerRid: "device-A")]
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "PUT" {
                let updated = DispatchSemaphore(value: 0)
                Task { @MainActor in
                    client.previewLightColor(id: lightId, xy: CIEXYColor(x: 0.6, y: 0.3))
                    updated.signal()
                }
                #expect(updated.wait(timeout: .now() + 2) == .success)
            }
            throw URLError(.notConnectedToInternet)
        }
        await #expect(throws: URLError.self) {
            try await client.setGroupedLightColor(id: groupId, xy: CIEXYColor(x: 0.2, y: 0.3), lightIds: [lightId])
        }
        #expect(client.lights[0].color?.xy.x == 0.6)
    }

    @Test func groupColorDebounceKeepsBridgeAndGroupCaptured() async throws {
        let clientA = makeClient()
        let clientB = makeClient()
        let groupA = "00000000-0000-0000-0000-000000000014"
        let groupB = "00000000-0000-0000-0000-000000000016"
        let lightId = "00000000-0000-0000-0000-000000000015"
        clientA.lights = [makeLight(id: lightId, name: "A", ownerRid: "device-A")]
        clientB.lights = [makeLight(id: lightId, name: "B", ownerRid: "device-B")]
        let paths = LockedValue<[String]>([])
        MockURLProtocol.requestHandler = { request in
            paths.set(paths.get() + [request.url!.path])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let change = GroupColorChange()
        change.schedule(client: clientA, id: groupA, lightIds: [lightId], xy: CIEXYColor(x: 0.2, y: 0.3))
        change.schedule(client: clientB, id: groupB, lightIds: [lightId], xy: CIEXYColor(x: 0.6, y: 0.3))
        await change.flush()?.value
        for _ in 0..<100 where paths.get().count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(Set(paths.get()) == Set([
            "/clip/v2/resource/grouped_light/\(groupA)",
            "/clip/v2/resource/grouped_light/\(groupB)",
        ]))
        #expect(clientA.lights[0].color?.xy.x == 0.2)
        #expect(clientB.lights[0].color?.xy.x == 0.6)
    }

    @Test func groupColorCancelledRequestReconcilesDespiteCallerCancellation() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000014"
        let lightId = "00000000-0000-0000-0000-000000000015"
        client.lights = [makeLight(id: lightId, name: "Lamp", ownerRid: "device-A")]
        let started = LockedValue(false)
        let release = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "PUT" {
                started.set(true)
                #expect(release.wait(timeout: .now() + 3) == .success)
                throw URLError(.cancelled)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"errors":[],"data":[{"id":"\(lightId)","owner":{"rid":"device-A","rtype":"device"},"metadata":{"name":"Lamp"},"on":{"on":true},"color":{"xy":{"x":0.4,"y":0.5}}}]}
            """
            return (response, Data(body.utf8))
        }
        let send = Task {
            try await client.setGroupedLightColor(id: groupId, xy: CIEXYColor(x: 0.4, y: 0.5), lightIds: [lightId])
        }
        defer { release.signal() }
        for _ in 0..<100 where !started.get() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(started.get())
        send.cancel()
        release.signal()
        await #expect(throws: URLError.self) { try await send.value }
        #expect(client.lights[0].color?.xy.x == 0.4)
    }

    @Test func groupColorFlushFailureRestoresOriginalAfterRepeatedPreviews() async throws {
        let client = makeClient()
        let groupId = "00000000-0000-0000-0000-000000000014"
        let lightId = "00000000-0000-0000-0000-000000000015"
        client.lights = [makeLight(id: lightId, name: "Lamp", ownerRid: "device-A")]
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let change = GroupColorChange()
        change.schedule(client: client, id: groupId, lightIds: [lightId], xy: CIEXYColor(x: 0.2, y: 0.3))
        change.schedule(client: client, id: groupId, lightIds: [lightId], xy: CIEXYColor(x: 0.6, y: 0.3))
        #expect(client.lights[0].color?.xy.x == 0.6)
        await change.flush()?.value
        #expect(client.lights[0].color == nil)
    }

    @Test func inactiveSceneEventClearsTrackedActiveScene() {
        let client = makeClient()
        client.activeSceneId = "s1"
        client.activeSceneIsDynamic = true
        client.scenes = [makeScene(id: "s1", name: "Relax", groupId: "room-1", status: .dynamicPalette)]

        client.applyEvents([
            makeUpdateEvent(
                resource: HueEventResource(
                    id: "s1",
                    type: "scene",
                    on: nil,
                    dimming: nil,
                    color: nil,
                    colorTemperature: nil,
                    status: HueSceneStatus(active: .inactive),
                    metadata: nil,
                    speed: nil
                )
            ),
        ])

        #expect(client.activeSceneId == nil)
        #expect(client.activeSceneIsDynamic == false)
        #expect(client.activeScene(for: "room-1") == nil)
    }

    @Test func setLightColorTemperatureMirekClamping() async throws {
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000004"
        client.lights = [makeLight(id: validId, name: "Lamp", ownerRid: "device-A")]

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Below min (153) should clamp
        try await client.setLightColorTemperature(id: validId, mirek: 50)
        #expect(client.lights.first?.colorTemperature?.mirek == 153)

        // Above max (500) should clamp
        try await client.setLightColorTemperature(id: validId, mirek: 999)
        #expect(client.lights.first?.colorTemperature?.mirek == 500)

        // Valid value should pass through
        try await client.setLightColorTemperature(id: validId, mirek: 300)
        #expect(client.lights.first?.colorTemperature?.mirek == 300)
    }

    @Test func recallSceneTracksActiveId() async throws {
        let client = makeClient()
        let sceneId = "00000000-0000-0000-0000-000000000005"

        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let path = request.url?.absoluteString ?? ""
            if path.contains("/resource/scene/") {
                #expect(request.httpMethod == "PUT")
            }
            // Return empty grouped_lights for the refresh call
            let json = #"{"errors":[],"data":[]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        try await client.recallScene(id: sceneId)
        #expect(client.activeSceneId == sceneId)
    }

    // MARK: - activeScene(for:) tests

    private func makeScene(
        id: String,
        name: String,
        groupId: String,
        status: HueSceneActiveState?,
        palette: HueScenePalette? = nil,
        speed: Double? = nil,
        autoDynamic: Bool? = nil
    ) -> HueScene {
        HueScene(
            id: id,
            type: "scene",
            metadata: HueSceneMetadata(name: name, image: nil),
            group: ResourceLink(rid: groupId, rtype: "room"),
            status: status.map { HueSceneStatus(active: $0) },
            palette: palette,
            speed: speed,
            autoDynamic: autoDynamic
        )
    }

    private func makeColorPalette(_ colors: [CIEXYColor]) -> HueScenePalette {
        HueScenePalette(
            color: colors.map { HueScenePaletteColor(color: HueColorValue(xy: $0), dimming: nil) },
            dimming: [],
            colorTemperature: []
        )
    }

    private struct TemperatureStop: Equatable {
        let mirek: Int
        let brightness: Double?
    }

    private func makeTemperaturePalette(_ mireks: [Int], brightness: Double? = nil) -> HueScenePalette {
        HueScenePalette(
            color: [],
            dimming: [],
            colorTemperature: mireks.map {
                HueScenePaletteColorTemp(
                    colorTemperature: HueColorTemperature(mirek: $0),
                    dimming: brightness.map { HueScenePaletteDimming(brightness: $0) }
                )
            }
        )
    }

    private func mireks(in entries: [ScenePaletteEntry]) -> [Int] {
        entries.compactMap { entry in
            if case .colorTemperature(let mirek, _) = entry {
                return mirek
            }
            return nil
        }
    }

    private func xyCount(in entries: [ScenePaletteEntry]) -> Int {
        entries.filter { entry in
            if case .xy = entry {
                return true
            }
            return false
        }.count
    }

    private func temperatureStops(in entries: [ScenePaletteEntry]) -> [TemperatureStop] {
        entries.compactMap { entry in
            if case .colorTemperature(let mirek, let brightness) = entry {
                return TemperatureStop(mirek: mirek, brightness: brightness)
            }
            return nil
        }
    }

    @Test func activeSceneReturnsStaticScene() {
        let client = makeClient()
        client.scenes = [
            makeScene(id: "s1", name: "Relax", groupId: "room-1", status: .inactive),
            makeScene(id: "s2", name: "Energize", groupId: "room-1", status: .static),
        ]

        let result = client.activeScene(for: "room-1")
        #expect(result?.id == "s2")
    }

    @Test func activeSceneReturnsNilWhenAllInactive() {
        let client = makeClient()
        client.scenes = [
            makeScene(id: "s1", name: "Relax", groupId: "room-1", status: .inactive),
        ]

        #expect(client.activeScene(for: "room-1") == nil)
    }

    @Test func previewPaletteUsesCurrentRoomLightsInsteadOfInactiveSceneFallback() {
        // Arrange
        let client = makeClient()
        client.rooms = [
            Room(
                id: "room-1",
                metadata: GroupMetadata(name: "Office", archetype: "office"),
                services: [],
                children: [
                    ResourceLink(rid: "device-1", rtype: "device"),
                    ResourceLink(rid: "device-2", rtype: "device"),
                ]
            ),
        ]
        client.lights = [
            makeLight(id: "light-1", name: "Desk", ownerRid: "device-1", mirek: 370),
            makeLight(id: "light-2", name: "Ceiling", ownerRid: "device-2", mirek: 370),
        ]
        client.scenes = [
            makeScene(
                id: "vapor-wave",
                name: "Vapor Wave",
                groupId: "room-1",
                status: .inactive,
                palette: makeColorPalette([
                    CIEXYColor(x: 0.167, y: 0.04),
                    CIEXYColor(x: 0.5, y: 0.2),
                ])
            ),
            makeScene(
                id: "bright",
                name: "Bright",
                groupId: "room-1",
                status: .inactive,
                palette: makeTemperaturePalette([370])
            ),
        ]

        // Act
        let entries = client.previewPaletteEntries(for: "room-1")

        // Assert
        #expect(mireks(in: entries) == [370, 370])
        #expect(xyCount(in: entries) == 0)
    }

    @Test func previewPaletteDoesNotUseInactiveSceneWhenCurrentLightsAreUnknown() {
        // Arrange
        let client = makeClient()
        client.scenes = [
            makeScene(
                id: "vapor-wave",
                name: "Vapor Wave",
                groupId: "room-1",
                status: .inactive,
                palette: makeColorPalette([
                    CIEXYColor(x: 0.167, y: 0.04),
                    CIEXYColor(x: 0.5, y: 0.2),
                ])
            ),
        ]

        // Act
        let entries = client.previewPaletteEntries(for: "room-1")

        // Assert
        #expect(entries.isEmpty)
    }

    @Test func previewPaletteUsesKnownActiveSceneWhenCurrentLightsAreUnavailable() {
        // Arrange
        let client = makeClient()
        client.scenes = [
            makeScene(
                id: "vapor-wave",
                name: "Vapor Wave",
                groupId: "room-1",
                status: .inactive,
                palette: makeColorPalette([
                    CIEXYColor(x: 0.167, y: 0.04),
                    CIEXYColor(x: 0.5, y: 0.2),
                ])
            ),
            makeScene(
                id: "bright",
                name: "Bright",
                groupId: "room-1",
                status: .static,
                palette: makeTemperaturePalette([370], brightness: 100)
            ),
        ]

        // Act
        let entries = client.previewPaletteEntries(for: "room-1")

        // Assert
        #expect(temperatureStops(in: entries) == [TemperatureStop(mirek: 370, brightness: 100)])
        #expect(xyCount(in: entries) == 0)
    }

    @Test func toggleLightRollbackOnHTTPFailure() async throws {
        let client = makeClient()
        let validId = "00000000-0000-0000-0000-000000000006"
        client.lights = [makeLight(id: validId, name: "Lamp", ownerRid: "device-A")]
        #expect(client.lights.first?.isOn == true)

        let lightsJSON = """
        {"errors":[],"data":[
            {"id":"\(validId)","owner":{"rid":"device-A","rtype":"device"},"metadata":{"name":"Lamp","archetype":"classic_bulb"},"on":{"on":true},"dimming":{"brightness":50.0}}
        ]}
        """

        var isFirstRequest = true
        MockURLProtocol.requestHandler = { request in
            if isFirstRequest {
                // First request: PUT toggle — return 500 to simulate failure
                isFirstRequest = false
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            // Second request: GET lights for rollback
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(lightsJSON.utf8))
        }

        await #expect(throws: HueAPIError.self) {
            try await client.toggleLight(id: validId, on: false)
        }
        // After rollback, light should be back to on
        #expect(client.lights.first?.isOn == true)
    }

    @Test func activeSceneReturnsDynamicPaletteScene() {
        let client = makeClient()
        client.scenes = [
            makeScene(id: "s1", name: "Relax", groupId: "room-1", status: .inactive),
            makeScene(id: "s2", name: "Energize", groupId: "room-1", status: .dynamicPalette),
        ]

        let result = client.activeScene(for: "room-1")
        #expect(result?.id == "s2")
    }

    @Test func recallSceneDynamicSendsCorrectAction() async throws {
        let client = makeClient()
        let sceneId = "00000000-0000-0000-0000-000000000010"

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.absoluteString ?? ""
            if path.contains("/resource/scene/") {
                #expect(request.httpMethod == "PUT")
                // Read body
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
                   let recall = body["recall"] as? [String: String] {
                    #expect(recall["action"] == "dynamic_palette")
                }
            }
            let json = #"{"errors":[],"data":[]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        try await client.recallScene(id: sceneId, dynamic: true)
        #expect(client.activeSceneId == sceneId)
        #expect(client.activeSceneIsDynamic == true)
    }

    @Test func setSceneSpeedOptimisticUpdateAndClamping() async throws {
        let client = makeClient()
        let sceneId = "00000000-0000-0000-0000-000000000011"
        client.scenes = [
            makeScene(id: sceneId, name: "Dynamic", groupId: "room-1", status: .dynamicPalette, speed: 0.5)
        ]

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // Normal value
        try await client.setSceneSpeed(id: sceneId, speed: 0.7)
        #expect(client.scenes.first?.speed == 0.7)

        // Above 1.0 should clamp
        try await client.setSceneSpeed(id: sceneId, speed: 1.5)
        #expect(client.scenes.first?.speed == 1.0)

        // Below 0.0 should clamp
        try await client.setSceneSpeed(id: sceneId, speed: -0.5)
        #expect(client.scenes.first?.speed == 0.0)
    }

    @Test func setSceneSpeedReRecallsActiveDynamicScene() async throws {
        let client = makeClient()
        let sceneId = "00000000-0000-0000-0000-000000000012"
        client.scenes = [
            makeScene(id: sceneId, name: "Dynamic", groupId: "room-1", status: .dynamicPalette, speed: 0.5)
        ]

        var sceneRequests: [[String: Any]] = []
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/resource/scene/\(sceneId)") == true {
                sceneRequests.append(self.jsonBody(from: request))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await client.setSceneSpeed(id: sceneId, speed: 0.7)

        #expect(sceneRequests.count == 2)
        #expect(sceneRequests[0]["speed"] as? Double == 0.7)
        let recall = sceneRequests.dropFirst().first?["recall"] as? [String: String]
        #expect(recall?["action"] == "dynamic_palette")
    }

    @Test func setSceneSpeedDoesNotRecallInactiveScene() async throws {
        let client = makeClient()
        let sceneId = "00000000-0000-0000-0000-000000000013"
        client.scenes = [
            makeScene(id: sceneId, name: "Dynamic", groupId: "room-1", status: .inactive, speed: 0.5)
        ]

        var sceneRequests: [[String: Any]] = []
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/resource/scene/\(sceneId)") == true {
                sceneRequests.append(self.jsonBody(from: request))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await client.setSceneSpeed(id: sceneId, speed: 0.7)

        #expect(sceneRequests.count == 1)
        #expect(sceneRequests[0]["speed"] as? Double == 0.7)
    }

    @Test func isActiveSceneDynamicReturnsCorrectValues() {
        let client = makeClient()
        client.scenes = [
            makeScene(id: "s1", name: "Static", groupId: "room-1", status: .static),
            makeScene(id: "s2", name: "Dynamic", groupId: "room-2", status: .dynamicPalette),
        ]

        #expect(client.isActiveSceneDynamic(for: "room-1") == false)
        #expect(client.isActiveSceneDynamic(for: "room-2") == true)
        #expect(client.isActiveSceneDynamic(for: nil) == false)
    }

    private func jsonBody(from request: URLRequest) -> [String: Any] {
        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            defer {
                buffer.deallocate()
                stream.close()
            }
            let read = stream.read(buffer, maxLength: 1024)
            if read > 0 { bodyData = Data(bytes: buffer, count: read) }
        }
        guard let bodyData,
              let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        else {
            return [:]
        }
        return body
    }

    private func makeLight(id: String, name: String, ownerRid: String, mirek: Int? = nil) -> HueLight {
        HueLight(
            id: id,
            owner: ResourceLink(rid: ownerRid, rtype: "device"),
            metadata: LightMetadata(name: name, archetype: "classic_bulb"),
            on: OnState(on: true),
            dimming: DimmingState(brightness: 50),
            color: nil,
            colorTemperature: mirek.map { LightColorTemperature(mirek: $0, mirekValid: true) }
        )
    }

    private func makeLightEventResource(id: String, on: Bool? = nil, brightness: Double? = nil) -> HueEventResource {
        HueEventResource(
            id: id,
            type: "light",
            on: on.map { OnState(on: $0) },
            dimming: brightness.map { DimmingState(brightness: $0) },
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )
    }

    private func makeGroupedLightEventResource(id: String, on: Bool) -> HueEventResource {
        HueEventResource(
            id: id,
            type: "grouped_light",
            on: OnState(on: on),
            dimming: nil,
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )
    }

    private func configureOfficeRoom(_ client: HueAPIClient, groupedLightId: String, lightIds: [String]) {
        client.rooms = [
            Room(
                id: "office-room",
                metadata: GroupMetadata(name: "Office", archetype: "office"),
                services: [ResourceLink(rid: groupedLightId, rtype: "grouped_light")],
                children: lightIds.map { ResourceLink(rid: "device-\($0)", rtype: "device") }
            ),
        ]
        client.groupedLights = [
            GroupedLight(id: groupedLightId, on: OnState(on: true), dimming: DimmingState(brightness: 80), colorTemperature: nil),
        ]
        client.lights = lightIds.map { makeLight(id: $0, name: $0, ownerRid: "device-\($0)") }
    }

    private func stubSuccessfulResponses() {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"errors":[],"data":[]}"#.utf8))
        }
    }

    private func makeUpdateEvent(resource: HueEventResource) -> HueEvent {
        makeUpdateEvent(resources: [resource])
    }

    private func makeUpdateEvent(resources: [HueEventResource]) -> HueEvent {
        HueEvent(
            creationtime: "2024-01-01T00:00:00Z",
            id: UUID().uuidString,
            type: .update,
            data: resources
        )
    }

    private func createEventStreamReconnectContext() -> (
        client: HueAPIClient,
        groupedLightRequestCount: () -> Int,
        eventStreamRequestCount: () -> Int
    ) {
        let client = makeClient()
        let groupedLightId = "00000000-0000-0000-0000-000000000099"
        let lock = NSLock()
        var groupedLightRequestCount = 0
        var eventStreamRequestCount = 0

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == "/eventstream/clip/v2" {
                lock.lock()
                eventStreamRequestCount += 1
                let currentRequestCount = eventStreamRequestCount
                lock.unlock()

                if currentRequestCount == 1 {
                    throw URLError(.networkConnectionLost)
                }

                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                return (response, Data(": keepalive\n\n".utf8))
            }

            let json: String
            if path.hasSuffix("/grouped_light") {
                lock.lock()
                groupedLightRequestCount += 1
                let isOn = groupedLightRequestCount == 1
                lock.unlock()

                json = """
                {"errors":[],"data":[
                    {"id":"\(groupedLightId)","on":{"on":\(isOn)},"dimming":{"brightness":80.0}}
                ]}
                """
            } else {
                json = #"{"errors":[],"data":[]}"#
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        return (
            client: client,
            groupedLightRequestCount: {
                lock.lock()
                defer { lock.unlock() }
                return groupedLightRequestCount
            },
            eventStreamRequestCount: {
                lock.lock()
                defer { lock.unlock() }
                return eventStreamRequestCount
            }
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<80 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
