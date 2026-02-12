import Foundation
import Testing
@testable import HueBar

@Suite("EventStreamUpdater")
struct EventStreamUpdaterTests {
    private let decoder = JSONDecoder()

    // MARK: - Helpers

    private func decodeGroupedLight(_ json: String) throws -> GroupedLight {
        try decoder.decode(GroupedLight.self, from: Data(json.utf8))
    }

    private func decodeLight(_ json: String) throws -> HueLight {
        try decoder.decode(HueLight.self, from: Data(json.utf8))
    }

    private func decodeEvent(_ json: String) throws -> HueEventResource {
        try decoder.decode(HueEventResource.self, from: Data(json.utf8))
    }

    // MARK: - GroupedLight tests

    @Test("Updating grouped_light on state preserves brightness")
    func groupedLightOnState() throws {
        var lights = [try decodeGroupedLight("""
            {"id":"gl-1","on":{"on":true},"dimming":{"brightness":75.0}}
        """)]
        let event = try decodeEvent("""
            {"id":"gl-1","type":"grouped_light","on":{"on":false}}
        """)

        EventStreamUpdater.apply(event, to: &lights)

        #expect(lights[0].isOn == false)
        #expect(lights[0].brightness == 75.0)
    }

    @Test("Updating grouped_light brightness preserves on state")
    func groupedLightBrightness() throws {
        var lights = [try decodeGroupedLight("""
            {"id":"gl-1","on":{"on":true},"dimming":{"brightness":50.0}}
        """)]
        let event = try decodeEvent("""
            {"id":"gl-1","type":"grouped_light","dimming":{"brightness":80.0}}
        """)

        EventStreamUpdater.apply(event, to: &lights)

        #expect(lights[0].isOn == true)
        #expect(lights[0].brightness == 80.0)
    }

    // MARK: - HueLight tests

    @Test("Updating light on state preserves other fields")
    func lightOnState() throws {
        var lights = [try decodeLight("""
            {"id":"light-1","owner":{"rid":"device-1","rtype":"device"},"metadata":{"name":"Desk Lamp","archetype":"table_wash"},"on":{"on":true},"dimming":{"brightness":60.0},"color":{"xy":{"x":0.5,"y":0.4}},"color_temperature":{"mirek":350,"mirek_valid":true}}
        """)]
        let event = try decodeEvent("""
            {"id":"light-1","type":"light","on":{"on":false}}
        """)

        EventStreamUpdater.apply(event, to: &lights)

        #expect(lights[0].isOn == false)
        #expect(lights[0].brightness == 60.0)
        #expect(lights[0].name == "Desk Lamp")
        #expect(lights[0].owner.rid == "device-1")
        #expect(lights[0].color?.xy.x == 0.5)
        #expect(lights[0].color_temperature?.mirek == 350)
    }

    // MARK: - Unknown ID

    @Test("Unknown ID is silently ignored")
    func unknownIdIgnored() throws {
        var groupedLights = [try decodeGroupedLight("""
            {"id":"gl-1","on":{"on":true},"dimming":{"brightness":50.0}}
        """)]
        var lights = [try decodeLight("""
            {"id":"light-1","owner":{"rid":"device-1","rtype":"device"},"metadata":{"name":"Lamp","archetype":"table_wash"},"on":{"on":true}}
        """)]
        let event = try decodeEvent("""
            {"id":"unknown-id","type":"light","on":{"on":false}}
        """)

        EventStreamUpdater.apply(event, to: &groupedLights)
        EventStreamUpdater.apply(event, to: &lights)

        #expect(groupedLights[0].isOn == true)
        #expect(lights[0].isOn == true)
    }
}
