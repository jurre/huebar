import Foundation
import Testing
@testable import HueBar

@Suite("EventStream decoding")
struct EventStreamTests {
    private let decoder = JSONDecoder()

    @Test("Decode update event with light on/dimming changes")
    func decodeLightUpdate() throws {
        let json = """
        [{"creationtime":"2024-02-06T09:34:09Z","id":"ev-1","type":"update","data":[{"id":"light-1","type":"light","on":{"on":true},"dimming":{"brightness":75.5}}]}]
        """.data(using: .utf8)!

        let events = try decoder.decode([HueEvent].self, from: json)
        #expect(events.count == 1)

        let event = events[0]
        #expect(event.id == "ev-1")
        #expect(event.type == HueEventType.update)
        #expect(event.creationtime == "2024-02-06T09:34:09Z")

        let resource = event.data[0]
        #expect(resource.id == "light-1")
        #expect(resource.type == "light")
        #expect(resource.on?.on == true)
        #expect(resource.dimming?.brightness == 75.5)
    }

    @Test("Decode grouped_light update event")
    func decodeGroupedLightUpdate() throws {
        let json = """
        [{"creationtime":"2024-02-06T10:00:00Z","id":"ev-2","type":"update","data":[{"id":"gl-1","type":"grouped_light","on":{"on":false},"dimming":{"brightness":50.0}}]}]
        """.data(using: .utf8)!

        let events = try decoder.decode([HueEvent].self, from: json)
        let resource = events[0].data[0]
        #expect(resource.type == "grouped_light")
        #expect(resource.on?.on == false)
        #expect(resource.dimming?.brightness == 50.0)
    }

    @Test("Decode scene status event")
    func decodeSceneStatus() throws {
        let json = """
        [{"creationtime":"2024-02-06T10:05:00Z","id":"ev-3","type":"update","data":[{"id":"scene-1","type":"scene","status":{"active":"inactive"}}]}]
        """.data(using: .utf8)!

        let events = try decoder.decode([HueEvent].self, from: json)
        let resource = events[0].data[0]
        #expect(resource.type == "scene")
        #expect(resource.status?.active == .inactive)
        #expect(resource.on == nil)
    }

    @Test("Decode add and delete event types")
    func decodeAddAndDelete() throws {
        let json = """
        [{"creationtime":"2024-02-06T11:00:00Z","id":"ev-4","type":"add","data":[{"id":"light-2","type":"light"}]},{"creationtime":"2024-02-06T11:01:00Z","id":"ev-5","type":"delete","data":[{"id":"light-3","type":"light"}]}]
        """.data(using: .utf8)!

        let events = try decoder.decode([HueEvent].self, from: json)
        #expect(events.count == 2)
        #expect(events[0].type == HueEventType.add)
        #expect(events[0].data[0].id == "light-2")
        #expect(events[1].type == HueEventType.delete)
        #expect(events[1].data[0].id == "light-3")
    }

    @Test("Decode color fields (xy and color_temperature)")
    func decodeColorFields() throws {
        let json = """
        [{"creationtime":"2024-02-06T12:00:00Z","id":"ev-6","type":"update","data":[{"id":"light-4","type":"light","color":{"xy":{"x":0.3127,"y":0.3290}},"color_temperature":{"mirek":250,"mirek_valid":true}}]}]
        """.data(using: .utf8)!

        let events = try decoder.decode([HueEvent].self, from: json)
        let resource = events[0].data[0]
        #expect(resource.color?.xy.x == 0.3127)
        #expect(resource.color?.xy.y == 0.3290)
        #expect(resource.colorTemperature?.mirek == 250)
        #expect(resource.colorTemperature?.mirekValid == true)
    }
}
