import Foundation

@Observable
@MainActor
final class RoomOrderManager {
    static let roomOrderKey = "huebar.roomOrder"
    static let zoneOrderKey = "huebar.zoneOrder"
    static let pinnedRoomsKey = "huebar.pinnedRooms"
    static let pinnedZonesKey = "huebar.pinnedZones"

    let defaults: UserDefaults

    private var cachedPinnedRooms: Set<String>
    private var cachedPinnedZones: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cachedPinnedRooms = Set(defaults.stringArray(forKey: Self.pinnedRoomsKey) ?? [])
        self.cachedPinnedZones = Set(defaults.stringArray(forKey: Self.pinnedZonesKey) ?? [])
    }

    // MARK: - Generic methods

    func pinnedIds(for key: String) -> Set<String> {
        switch key {
        case Self.pinnedRoomsKey: return cachedPinnedRooms
        case Self.pinnedZonesKey: return cachedPinnedZones
        default: return Set(defaults.stringArray(forKey: key) ?? [])
        }
    }

    func isPinned(_ id: String, key: String) -> Bool {
        pinnedIds(for: key).contains(id)
    }

    func togglePin<T: LightGroup>(_ id: String, groups: inout [T], pinnedKey: String) {
        var pinned = pinnedIds(for: pinnedKey)
        if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) }
        defaults.set(Array(pinned), forKey: pinnedKey)
        updateCache(pinned, for: pinnedKey)
        sort(&groups, pinnedKey: pinnedKey)
    }

    func sort<T: LightGroup>(_ groups: inout [T], pinnedKey: String) {
        let pinned = pinnedIds(for: pinnedKey)
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

    private func updateCache(_ pinned: Set<String>, for key: String) {
        switch key {
        case Self.pinnedRoomsKey: cachedPinnedRooms = pinned
        case Self.pinnedZonesKey: cachedPinnedZones = pinned
        default: break
        }
    }

    func isRoomPinned(_ id: String) -> Bool { isPinned(id, key: Self.pinnedRoomsKey) }
    func isZonePinned(_ id: String) -> Bool { isPinned(id, key: Self.pinnedZonesKey) }

    func toggleRoomPin(_ id: String, rooms: inout [Room]) { togglePin(id, groups: &rooms, pinnedKey: Self.pinnedRoomsKey) }
    func toggleZonePin(_ id: String, zones: inout [Zone]) { togglePin(id, groups: &zones, pinnedKey: Self.pinnedZonesKey) }

    func sortRooms(_ rooms: inout [Room]) { sort(&rooms, pinnedKey: Self.pinnedRoomsKey) }
    func sortZones(_ zones: inout [Zone]) { sort(&zones, pinnedKey: Self.pinnedZonesKey) }

    func moveRoom(fromId: String, toId: String, rooms: inout [Room]) { move(in: &rooms, fromId: fromId, toId: toId, orderKey: Self.roomOrderKey) }
    func moveZone(fromId: String, toId: String, zones: inout [Zone]) { move(in: &zones, fromId: fromId, toId: toId, orderKey: Self.zoneOrderKey) }
}
