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

    @Test func lightDecodingWithColor() throws {
        let json = """
        {
            "id": "light-1",
            "owner": {"rid": "device-1", "rtype": "device"},
            "metadata": {"name": "Desk Lamp", "archetype": "table_wash"},
            "on": {"on": true},
            "dimming": {"brightness": 75.5},
            "color": {"xy": {"x": 0.5, "y": 0.4}},
            "color_temperature": {"mirek": 350, "mirek_valid": true}
        }
        """
        let light = try decoder.decode(HueLight.self, from: Data(json.utf8))
        #expect(light.id == "light-1")
        #expect(light.name == "Desk Lamp")
        #expect(light.isOn == true)
        #expect(light.brightness == 75.5)
        #expect(light.owner.rid == "device-1")
        #expect(light.color?.xy.x == 0.5)
        #expect(light.colorTemperature?.mirek == 350)
    }

    @Test func lightDecodingWhiteOnly() throws {
        let json = """
        {
            "id": "light-2",
            "owner": {"rid": "device-2", "rtype": "device"},
            "metadata": {"name": "Ceiling", "archetype": "ceiling_round"},
            "on": {"on": false},
            "dimming": {"brightness": 50.0}
        }
        """
        let light = try decoder.decode(HueLight.self, from: Data(json.utf8))
        #expect(light.id == "light-2")
        #expect(light.isOn == false)
        #expect(light.color == nil)
        #expect(light.colorTemperature == nil)
    }

    // MARK: - Scene paletteColors

    @Test func scenePaletteColorsFromXY() throws {
        let json = """
        {
            "id": "scene-1",
            "metadata": {"name": "Tropical"},
            "group": {"rid": "room-1", "rtype": "room"},
            "palette": {
                "color": [
                    {"color": {"xy": {"x": 0.5, "y": 0.4}}, "dimming": {"brightness": 80.0}},
                    {"color": {"xy": {"x": 0.3, "y": 0.6}}, "dimming": {"brightness": 50.0}}
                ],
                "dimming": []
            }
        }
        """
        let scene = try decoder.decode(HueScene.self, from: Data(json.utf8))
        #expect(scene.paletteColors.count == 2)
    }

    @Test func scenePaletteColorsFromColorTemperature() throws {
        let json = """
        {
            "id": "scene-2",
            "metadata": {"name": "Warm"},
            "group": {"rid": "room-1", "rtype": "room"},
            "palette": {
                "color": [],
                "dimming": [],
                "color_temperature": [
                    {"color_temperature": {"mirek": 350}, "dimming": {"brightness": 100.0}},
                    {"color_temperature": {"mirek": 250}, "dimming": {"brightness": 60.0}}
                ]
            }
        }
        """
        let scene = try decoder.decode(HueScene.self, from: Data(json.utf8))
        #expect(scene.paletteColors.count == 2)
        #expect(scene.hasPalette == true)
    }

    @Test func scenePaletteColorsEmptyPalette() throws {
        let json = """
        {
            "id": "scene-3",
            "metadata": {"name": "Empty"},
            "group": {"rid": "room-1", "rtype": "room"},
            "palette": {
                "color": [],
                "dimming": []
            }
        }
        """
        let scene = try decoder.decode(HueScene.self, from: Data(json.utf8))
        #expect(scene.paletteColors.isEmpty)
    }

    @Test func scenePaletteColorsNoPalette() throws {
        let json = """
        {
            "id": "scene-4",
            "metadata": {"name": "Basic"},
            "group": {"rid": "room-1", "rtype": "room"}
        }
        """
        let scene = try decoder.decode(HueScene.self, from: Data(json.utf8))
        #expect(scene.paletteColors.isEmpty)
    }

    // MARK: - Dynamic scene fields

    @Test func sceneWithDynamicFields() throws {
        let json = """
        {
            "id": "scene-dyn",
            "metadata": {"name": "Dynamic Scene"},
            "group": {"rid": "room-1", "rtype": "room"},
            "status": {"active": "dynamic_palette"},
            "speed": 0.75,
            "auto_dynamic": true,
            "palette": {
                "color": [
                    {"color": {"xy": {"x": 0.5, "y": 0.4}}, "dimming": {"brightness": 80.0}}
                ],
                "dimming": []
            }
        }
        """
        let scene = try decoder.decode(HueScene.self, from: Data(json.utf8))
        #expect(scene.id == "scene-dyn")
        #expect(scene.status?.active == .dynamicPalette)
        #expect(scene.speed == 0.75)
        #expect(scene.autoDynamic == true)
        #expect(scene.isDynamicActive == true)
        #expect(scene.hasPalette == true)
    }

    @Test func sceneWithoutDynamicFieldsBackwardCompat() throws {
        let json = """
        {
            "id": "scene-static",
            "metadata": {"name": "Static Scene"},
            "group": {"rid": "room-1", "rtype": "room"},
            "status": {"active": "static"}
        }
        """
        let scene = try decoder.decode(HueScene.self, from: Data(json.utf8))
        #expect(scene.speed == nil)
        #expect(scene.autoDynamic == nil)
        #expect(scene.isDynamicActive == false)
        #expect(scene.hasPalette == false)
    }

    // MARK: - supportsDynamic

    @Test func supportsDynamicWithPaletteOnly() throws {
        let json = """
        {
            "id": "scene-palette",
            "metadata": {"name": "With Palette"},
            "group": {"rid": "room-1", "rtype": "room"},
            "palette": {"color": [], "color_temperature": [{"color_temperature": {"mirek": 350}}]}
        }
        """
        let scene = try decoder.decode(HueScene.self, from: Data(json.utf8))
        #expect(scene.supportsDynamic == true)
    }

    @Test func supportsDynamicWithAutoDynamicOnly() throws {
        let json = """
        {
            "id": "scene-auto",
            "metadata": {"name": "Auto Dynamic"},
            "group": {"rid": "room-1", "rtype": "room"},
            "auto_dynamic": true
        }
        """
        let scene = try decoder.decode(HueScene.self, from: Data(json.utf8))
        #expect(scene.supportsDynamic == true)
    }

    @Test func supportsDynamicFalseWhenNoPaletteAndNoAutoDynamic() throws {
        let json = """
        {
            "id": "scene-none",
            "metadata": {"name": "No Dynamic"},
            "group": {"rid": "room-1", "rtype": "room"}
        }
        """
        let scene = try decoder.decode(HueScene.self, from: Data(json.utf8))
        #expect(scene.supportsDynamic == false)
    }

    // MARK: - Event stream speed decoding

    @Test func eventResourceDecodesSpeedField() throws {
        let json = """
        {
            "id": "scene-1",
            "type": "scene",
            "speed": 0.42,
            "status": {"active": "dynamic_palette"}
        }
        """
        let resource = try decoder.decode(HueEventResource.self, from: Data(json.utf8))
        #expect(resource.speed == 0.42)
        #expect(resource.status?.active == .dynamicPalette)
    }
}
