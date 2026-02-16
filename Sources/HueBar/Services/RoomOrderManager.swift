import Foundation

@Observable
@MainActor
final class RoomOrderManager {
    enum PinCategory: Sendable {
        case rooms
        case zones

        var key: String {
            switch self {
            case .rooms: "huebar.pinnedRooms"
            case .zones: "huebar.pinnedZones"
            }
        }
    }

    static let roomOrderKey = "huebar.roomOrder"
    static let zoneOrderKey = "huebar.zoneOrder"

    let defaults: UserDefaults

    private var cachedPinnedRooms: Set<String>
    private var cachedPinnedZones: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cachedPinnedRooms = Set(defaults.stringArray(forKey: PinCategory.rooms.key) ?? [])
        self.cachedPinnedZones = Set(defaults.stringArray(forKey: PinCategory.zones.key) ?? [])
    }

    // MARK: - Generic methods

    func pinnedIds(for category: PinCategory) -> Set<String> {
        switch category {
        case .rooms: return cachedPinnedRooms
        case .zones: return cachedPinnedZones
        }
    }

    func isPinned(_ id: String, category: PinCategory) -> Bool {
        pinnedIds(for: category).contains(id)
    }

    func togglePin<T: LightGroup>(_ id: String, groups: inout [T], category: PinCategory) {
        var pinned = pinnedIds(for: category)
        if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) }
        defaults.set(Array(pinned), forKey: category.key)
        updateCache(pinned, for: category)
        sort(&groups, category: category)
    }

    func sort<T: LightGroup>(_ groups: inout [T], category: PinCategory) {
        let pinned = pinnedIds(for: category)
        let orderKey = category == .rooms ? Self.roomOrderKey : Self.zoneOrderKey
        let customOrder = defaults.stringArray(forKey: orderKey) ?? []
        
        // Build a dictionary for O(1) lookup of custom positions
        var orderIndex: [String: Int] = [:]
        for (index, id) in customOrder.enumerated() {
            orderIndex[id] = index
        }
        
        groups.sort {
            let aPinned = pinned.contains($0.id)
            let bPinned = pinned.contains($1.id)
            
            // Pinned items always come first
            if aPinned != bPinned { return aPinned }
            
            // Among pinned or unpinned items, use custom order if available
            let aIndex = orderIndex[$0.id]
            let bIndex = orderIndex[$1.id]
            
            switch (aIndex, bIndex) {
            case let (.some(a), .some(b)):
                // Both have custom positions - use those
                return a < b
            case (.some, .none):
                // Only A has custom position - A comes first
                return true
            case (.none, .some):
                // Only B has custom position - B comes first
                return false
            case (.none, .none):
                // Neither has custom position - fall back to alphabetical
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    func move<T: LightGroup>(in groups: inout [T], fromId: String, toId: String, orderKey: String, category: PinCategory) {
        guard let fromIndex = groups.firstIndex(where: { $0.id == fromId }),
              let toIndex = groups.firstIndex(where: { $0.id == toId }),
              fromIndex != toIndex else { return }
        let item = groups.remove(at: fromIndex)
        groups.insert(item, at: toIndex)
        defaults.set(groups.map(\.id), forKey: orderKey)
        // Re-sort to preserve pin priority invariant
        sort(&groups, category: category)
    }

    func moveToEdge<T: LightGroup>(in groups: inout [T], id: String, toTop: Bool, orderKey: String, category: PinCategory) {
        guard let fromIndex = groups.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = toTop ? 0 : groups.count - 1
        guard fromIndex != targetIndex else { return }
        let item = groups.remove(at: fromIndex)
        groups.insert(item, at: targetIndex)
        defaults.set(groups.map(\.id), forKey: orderKey)
        // Re-sort to preserve pin priority invariant
        sort(&groups, category: category)
    }

    // MARK: - Convenience wrappers

    var pinnedRoomIds: Set<String> { cachedPinnedRooms }
    var pinnedZoneIds: Set<String> { cachedPinnedZones }

    // MARK: - Private

    private func updateCache(_ pinned: Set<String>, for category: PinCategory) {
        switch category {
        case .rooms: cachedPinnedRooms = pinned
        case .zones: cachedPinnedZones = pinned
        }
    }

    func isRoomPinned(_ id: String) -> Bool { isPinned(id, category: .rooms) }
    func isZonePinned(_ id: String) -> Bool { isPinned(id, category: .zones) }

    func toggleRoomPin(_ id: String, rooms: inout [Room]) { togglePin(id, groups: &rooms, category: .rooms) }
    func toggleZonePin(_ id: String, zones: inout [Zone]) { togglePin(id, groups: &zones, category: .zones) }

    func sortRooms(_ rooms: inout [Room]) { sort(&rooms, category: .rooms) }
    func sortZones(_ zones: inout [Zone]) { sort(&zones, category: .zones) }

    func moveRoom(fromId: String, toId: String, rooms: inout [Room]) { move(in: &rooms, fromId: fromId, toId: toId, orderKey: Self.roomOrderKey, category: .rooms) }
    func moveZone(fromId: String, toId: String, zones: inout [Zone]) { move(in: &zones, fromId: fromId, toId: toId, orderKey: Self.zoneOrderKey, category: .zones) }

    func moveRoomToTop(id: String, rooms: inout [Room]) { moveToEdge(in: &rooms, id: id, toTop: true, orderKey: Self.roomOrderKey, category: .rooms) }
    func moveRoomToBottom(id: String, rooms: inout [Room]) { moveToEdge(in: &rooms, id: id, toTop: false, orderKey: Self.roomOrderKey, category: .rooms) }
    func moveZoneToTop(id: String, zones: inout [Zone]) { moveToEdge(in: &zones, id: id, toTop: true, orderKey: Self.zoneOrderKey, category: .zones) }
    func moveZoneToBottom(id: String, zones: inout [Zone]) { moveToEdge(in: &zones, id: id, toTop: false, orderKey: Self.zoneOrderKey, category: .zones) }
}
