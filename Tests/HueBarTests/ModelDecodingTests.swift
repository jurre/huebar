import Foundation
import Testing
@testable import HueBar

struct ModelDecodingTests {
    private let decoder = JSONDecoder()

    @Test func roomDecoding() throws {
        let json = """
        {"id":"abc-123","metadata":{"name":"Living Room","archetype":"living_room"},"services":[{"rid":"gl-1","rtype":"grouped_light"},{"rid":"light-1","rtype":"light"}],"children":[{"rid":"light-1","rtype":"device"}]}
        """
        let room = try decoder.decode(Room.self, from: Data(json.utf8))
        #expect(room.id == "abc-123")
        #expect(room.name == "Living Room")
        #expect(room.groupedLightId == "gl-1")
        #expect(room.children.count == 1)
    }

    @Test func roomWithNoGroupedLight() throws {
        let json = """
        {"id":"room-2","metadata":{"name":"Hallway","archetype":"hallway"},"services":[{"rid":"light-1","rtype":"light"}],"children":[]}
        """
        let room = try decoder.decode(Room.self, from: Data(json.utf8))
        #expect(room.groupedLightId == nil)
    }

    @Test func zoneDecoding() throws {
        let json = """
        {"id":"zone-1","metadata":{"name":"Downstairs","archetype":"home"},"services":[{"rid":"gl-2","rtype":"grouped_light"}],"children":[{"rid":"room-1","rtype":"room"}]}
        """
        let zone = try decoder.decode(Zone.self, from: Data(json.utf8))
        #expect(zone.id == "zone-1")
        #expect(zone.name == "Downstairs")
        #expect(zone.groupedLightId == "gl-2")
        #expect(zone.children.count == 1)
    }

    @Test func groupedLightDecoding() throws {
        let json = """
        {"id":"gl-1","on":{"on":true},"dimming":{"brightness":75.0}}
        """
        let light = try decoder.decode(GroupedLight.self, from: Data(json.utf8))
        #expect(light.id == "gl-1")
        #expect(light.isOn == true)
        #expect(light.brightness == 75.0)
    }

    @Test func groupedLightOff() throws {
        let json = """
        {"id":"gl-2","on":{"on":false},"dimming":{"brightness":0.0}}
        """
        let light = try decoder.decode(GroupedLight.self, from: Data(json.utf8))
        #expect(light.isOn == false)
    }

    @Test func groupedLightMissingOptionalFields() throws {
        let json = """
        {"id":"gl-3"}
        """
        let light = try decoder.decode(GroupedLight.self, from: Data(json.utf8))
        #expect(light.isOn == false)
        #expect(light.brightness == 0.0)
    }

    @Test func hueResponseDecoding() throws {
        let json = """
        {"errors":[],"data":[{"id":"gl-1","on":{"on":true},"dimming":{"brightness":50.0}}]}
        """
        let response = try decoder.decode(HueResponse<GroupedLight>.self, from: Data(json.utf8))
        #expect(response.errors.isEmpty)
        #expect(response.data.count == 1)
        #expect(response.data[0].brightness == 50.0)
    }

    @Test func hueResponseWithErrors() throws {
        let json = """
        {"errors":[{"description":"resource not found"}],"data":[]}
        """
        let response = try decoder.decode(HueResponse<GroupedLight>.self, from: Data(json.utf8))
        #expect(response.errors.count == 1)
        #expect(response.errors[0].description == "resource not found")
        #expect(response.data.isEmpty)
    }

    @Test func sceneDecoding() throws {
        let json = """
        {
            "id": "abc-123",
            "metadata": {"name": "Relax"},
            "group": {"rid": "room-456", "rtype": "room"},
            "status": {"active": "inactive"}
        }
        """.data(using: .utf8)!
        let scene = try JSONDecoder().decode(HueScene.self, from: json)
        #expect(scene.id == "abc-123")
        #expect(scene.name == "Relax")
        #expect(scene.group.rid == "room-456")
        #expect(scene.group.rtype == "room")
    }

    @Test func sceneWithoutStatus() throws {
        let json = """
        {
            "id": "abc-123",
            "metadata": {"name": "Energize"},
            "group": {"rid": "zone-789", "rtype": "zone"}
        }
        """.data(using: .utf8)!
        let scene = try JSONDecoder().decode(HueScene.self, from: json)
        #expect(scene.name == "Energize")
        #expect(scene.status == nil)
    }
}
