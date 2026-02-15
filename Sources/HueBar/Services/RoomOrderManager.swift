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
        groups.sort {
            let aPinned = pinned.contains($0.id)
            let bPinned = pinned.contains($1.id)
            if aPinned != bPinned { return aPinned }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func move<T: LightGroup>(in groups: inout [T], fromId: String, toId: String, orderKey: String) {
        guard let fromIndex = groups.firstIndex(where: { $0.id == fromId }),
              let toIndex = groups.firstIndex(where: { $0.id == toId }),
              fromIndex != toIndex else { return }
        let item = groups.remove(at: fromIndex)
        groups.insert(item, at: toIndex)
        defaults.set(groups.map(\.id), forKey: orderKey)
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

    func moveRoom(fromId: String, toId: String, rooms: inout [Room]) { move(in: &rooms, fromId: fromId, toId: toId, orderKey: Self.roomOrderKey) }
    func moveZone(fromId: String, toId: String, zones: inout [Zone]) { move(in: &zones, fromId: fromId, toId: toId, orderKey: Self.zoneOrderKey) }
}
