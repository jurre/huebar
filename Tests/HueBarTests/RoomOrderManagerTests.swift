import Foundation
import Testing

@testable import HueBar

private struct FakeGroup: LightGroup {
    let id: String
    let name: String
    var services: [ResourceLink] { [] }
    var children: [ResourceLink] { [] }
    var groupedLightId: String? { nil }
}

@Suite(.serialized)
@MainActor
struct RoomOrderManagerTests {
    private let suiteName = "test-room-order"
    private let pinnedKey = RoomOrderManager.pinnedRoomsKey
    private let orderKey = RoomOrderManager.roomOrderKey

    private func makeManager() -> (RoomOrderManager, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let manager = RoomOrderManager(defaults: defaults)
        return (manager, defaults)
    }

    // MARK: - sort

    @Test func sortPinnedFirst() {
        let (_, defaults) = makeManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(["2"], forKey: pinnedKey)
        let mgr = RoomOrderManager(defaults: defaults)

        var groups = [
            FakeGroup(id: "1", name: "Kitchen"),
            FakeGroup(id: "2", name: "Bedroom"),
            FakeGroup(id: "3", name: "Attic"),
        ]
        mgr.sort(&groups, pinnedKey: pinnedKey)

        #expect(groups.map(\.id) == ["2", "3", "1"])
    }

    @Test func sortAlphabeticallyWhenNoPins() {
        let (manager, _defaults) = makeManager()
        defer { _defaults.removePersistentDomain(forName: suiteName) }

        var groups = [
            FakeGroup(id: "1", name: "Kitchen"),
            FakeGroup(id: "2", name: "Bedroom"),
            FakeGroup(id: "3", name: "Attic"),
        ]
        manager.sort(&groups, pinnedKey: pinnedKey)

        #expect(groups.map(\.name) == ["Attic", "Bedroom", "Kitchen"])
    }

    // MARK: - togglePin

    @Test func togglePinAddsAndRemoves() {
        let (manager, defaults) = makeManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var groups = [
            FakeGroup(id: "1", name: "Kitchen"),
            FakeGroup(id: "2", name: "Bedroom"),
        ]

        // Pin id "2"
        manager.togglePin("2", groups: &groups, pinnedKey: pinnedKey)
        #expect(manager.pinnedIds(for: pinnedKey).contains("2"))
        #expect(groups.first?.id == "2")

        // Unpin id "2"
        manager.togglePin("2", groups: &groups, pinnedKey: pinnedKey)
        #expect(!manager.pinnedIds(for: pinnedKey).contains("2"))
    }

    @Test func togglePinPersistsToDefaults() {
        let (manager, defaults) = makeManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var groups = [FakeGroup(id: "a", name: "Alpha")]
        manager.togglePin("a", groups: &groups, pinnedKey: pinnedKey)

        let stored = Set(defaults.stringArray(forKey: pinnedKey) ?? [])
        #expect(stored.contains("a"))
    }

    // MARK: - move

    @Test func moveReordersItems() {
        let (manager, defaults) = makeManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var groups = [
            FakeGroup(id: "1", name: "A"),
            FakeGroup(id: "2", name: "B"),
            FakeGroup(id: "3", name: "C"),
        ]
        manager.move(in: &groups, fromId: "3", toId: "1", orderKey: orderKey)

        #expect(groups.map(\.id) == ["3", "1", "2"])
        #expect(defaults.stringArray(forKey: orderKey) == ["3", "1", "2"])
    }

    @Test func moveSameIndexIsNoOp() {
        let (manager, defaults) = makeManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var groups = [
            FakeGroup(id: "1", name: "A"),
            FakeGroup(id: "2", name: "B"),
        ]
        manager.move(in: &groups, fromId: "1", toId: "1", orderKey: orderKey)

        #expect(groups.map(\.id) == ["1", "2"])
        #expect(defaults.stringArray(forKey: orderKey) == nil)
    }
}
