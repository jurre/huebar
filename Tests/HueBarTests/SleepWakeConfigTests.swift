import Testing
import Foundation
@testable import HueBar

@Suite("SleepWakeConfig Tests")
struct SleepWakeConfigTests {

    // MARK: - SleepWakeMode raw values

    @Test("SleepWakeMode raw values match expected strings")
    func sleepWakeModeRawValues() {
        #expect(SleepWakeMode.sleepOnly.rawValue == "sleep")
        #expect(SleepWakeMode.wakeOnly.rawValue == "wake")
        #expect(SleepWakeMode.both.rawValue == "both")
    }

    @Test("SleepWakeMode decodes from raw value strings")
    func sleepWakeModeDecoding() throws {
        for mode in SleepWakeMode.allCases {
            let json = "\"\(mode.rawValue)\""
            let decoded = try JSONDecoder().decode(SleepWakeMode.self, from: Data(json.utf8))
            #expect(decoded == mode)
        }
    }

    @Test("SleepWakeMode Codable round-trip")
    func sleepWakeModeCodableRoundTrip() throws {
        for mode in SleepWakeMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SleepWakeMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    // MARK: - SleepWakeConfig id

    @Test("id computed property equals targetId")
    func idEqualsTargetId() {
        let config = SleepWakeConfig(
            targetType: .room, targetId: "room-123",
            targetName: "Bedroom", mode: .both,
            wakeSceneId: nil, wakeSceneName: nil
        )
        #expect(config.id == config.targetId)
        #expect(config.id == "room-123")
    }

    // MARK: - SleepWakeConfig Codable round-trip

    @Test("SleepWakeConfig Codable round-trip with all fields")
    func configCodableRoundTrip() throws {
        let original = SleepWakeConfig(
            targetType: .zone, targetId: "zone-456",
            targetName: "Upstairs", mode: .wakeOnly,
            wakeSceneId: "scene-789", wakeSceneName: "Morning"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SleepWakeConfig.self, from: data)

        #expect(decoded.targetType == original.targetType)
        #expect(decoded.targetId == original.targetId)
        #expect(decoded.targetName == original.targetName)
        #expect(decoded.mode == original.mode)
        #expect(decoded.wakeSceneId == original.wakeSceneId)
        #expect(decoded.wakeSceneName == original.wakeSceneName)
    }

    @Test("SleepWakeConfig Codable round-trip with nil optionals")
    func configCodableRoundTripNils() throws {
        let original = SleepWakeConfig(
            targetType: .room, targetId: "room-abc",
            targetName: "Kitchen", mode: .sleepOnly,
            wakeSceneId: nil, wakeSceneName: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SleepWakeConfig.self, from: data)

        #expect(decoded.wakeSceneId == nil)
        #expect(decoded.wakeSceneName == nil)
        #expect(decoded.mode == .sleepOnly)
    }
}
