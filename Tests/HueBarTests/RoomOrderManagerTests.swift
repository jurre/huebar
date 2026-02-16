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
    private let pinnedCategory = RoomOrderManager.PinCategory.rooms
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

        defaults.set(["2"], forKey: pinnedCategory.key)
        let mgr = RoomOrderManager(defaults: defaults)

        var groups = [
            FakeGroup(id: "1", name: "Kitchen"),
            FakeGroup(id: "2", name: "Bedroom"),
            FakeGroup(id: "3", name: "Attic"),
        ]
        mgr.sort(&groups, category: pinnedCategory)

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
        manager.sort(&groups, category: pinnedCategory)

        #expect(groups.map(\.name) == ["Attic", "Bedroom", "Kitchen"])
    }
    
    @Test func sortRespectsCustomOrder() {
        let (manager, defaults) = makeManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Set custom order: 3, 1, 2
        defaults.set(["3", "1", "2"], forKey: orderKey)

        var groups = [
            FakeGroup(id: "1", name: "Kitchen"),
            FakeGroup(id: "2", name: "Bedroom"),
            FakeGroup(id: "3", name: "Attic"),
        ]
        manager.sort(&groups, category: pinnedCategory)

        // Should follow custom order, not alphabetical
        #expect(groups.map(\.id) == ["3", "1", "2"])
    }
    
    @Test func sortRespectsCustomOrderWithPins() {
        let (_, defaults) = makeManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Pin item "2" and set custom order for unpinned: 3, 1
        defaults.set(["2"], forKey: pinnedCategory.key)
        defaults.set(["3", "1", "2"], forKey: orderKey)
        let mgr = RoomOrderManager(defaults: defaults)

        var groups = [
            FakeGroup(id: "1", name: "Kitchen"),
            FakeGroup(id: "2", name: "Bedroom"),
            FakeGroup(id: "3", name: "Attic"),
        ]
        mgr.sort(&groups, category: pinnedCategory)

        // Pinned items first, then custom order for unpinned
        #expect(groups.map(\.id) == ["2", "3", "1"])
    }
    
    @Test func sortFallsBackToAlphabeticalForUnorderedItems() {
        let (manager, defaults) = makeManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Only set custom order for item "1"
        defaults.set(["1"], forKey: orderKey)

        var groups = [
            FakeGroup(id: "1", name: "Kitchen"),
            FakeGroup(id: "2", name: "Bedroom"),
            FakeGroup(id: "3", name: "Attic"),
        ]
        manager.sort(&groups, category: pinnedCategory)

        // Item "1" comes first (has custom order), then "3" and "2" alphabetically
        #expect(groups.map(\.id) == ["1", "3", "2"])
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
        manager.togglePin("2", groups: &groups, category: pinnedCategory)
        #expect(manager.pinnedIds(for: pinnedCategory).contains("2"))
        #expect(groups.first?.id == "2")

        // Unpin id "2"
        manager.togglePin("2", groups: &groups, category: pinnedCategory)
        #expect(!manager.pinnedIds(for: pinnedCategory).contains("2"))
    }

    @Test func togglePinPersistsToDefaults() {
        let (manager, defaults) = makeManager()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var groups = [FakeGroup(id: "a", name: "Alpha")]
        manager.togglePin("a", groups: &groups, category: pinnedCategory)

        let stored = Set(defaults.stringArray(forKey: pinnedCategory.key) ?? [])
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
