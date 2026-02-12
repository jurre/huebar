import Foundation

@Observable
@MainActor
final class RoomOrderManager {
    static let roomOrderKey = "huebar.roomOrder"
    static let zoneOrderKey = "huebar.zoneOrder"
    static let pinnedRoomsKey = "huebar.pinnedRooms"
    static let pinnedZonesKey = "huebar.pinnedZones"

    var pinnedRoomIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.pinnedRoomsKey) ?? [])
    }

    var pinnedZoneIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.pinnedZonesKey) ?? [])
    }

    func isRoomPinned(_ id: String) -> Bool { pinnedRoomIds.contains(id) }
    func isZonePinned(_ id: String) -> Bool { pinnedZoneIds.contains(id) }

    func toggleRoomPin(_ id: String, rooms: inout [Room]) {
        var pinned = pinnedRoomIds
        if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) }
        UserDefaults.standard.set(Array(pinned), forKey: Self.pinnedRoomsKey)
        sortRooms(&rooms)
    }

    func toggleZonePin(_ id: String, zones: inout [Zone]) {
        var pinned = pinnedZoneIds
        if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) }
        UserDefaults.standard.set(Array(pinned), forKey: Self.pinnedZonesKey)
        sortZones(&zones)
    }

    func sortRooms(_ rooms: inout [Room]) {
        let pinned = pinnedRoomIds
        rooms.sort {
            let aPinned = pinned.contains($0.id)
            let bPinned = pinned.contains($1.id)
            if aPinned != bPinned { return aPinned }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func sortZones(_ zones: inout [Zone]) {
        let pinned = pinnedZoneIds
        zones.sort {
            let aPinned = pinned.contains($0.id)
            let bPinned = pinned.contains($1.id)
            if aPinned != bPinned { return aPinned }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func moveRoom(fromId: String, toId: String, rooms: inout [Room]) {
        reorder(&rooms, fromId: fromId, toId: toId)
        saveOrder(rooms, key: Self.roomOrderKey)
    }

    func moveZone(fromId: String, toId: String, zones: inout [Zone]) {
        reorder(&zones, fromId: fromId, toId: toId)
        saveOrder(zones, key: Self.zoneOrderKey)
    }

    func reorder<T: Identifiable>(_ items: inout [T], fromId: String, toId: String) where T.ID == String {
        guard let fromIndex = items.firstIndex(where: { $0.id == fromId }),
              let toIndex = items.firstIndex(where: { $0.id == toId }),
              fromIndex != toIndex else { return }
        let item = items.remove(at: fromIndex)
        items.insert(item, at: toIndex)
    }

    func saveOrder<T: Identifiable>(_ items: [T], key: String) where T.ID == String {
        UserDefaults.standard.set(items.map(\.id), forKey: key)
    }

    func applySavedOrder<T: Identifiable>(_ items: [T], key: String) -> [T] where T.ID == String {
        guard let savedOrder = UserDefaults.standard.stringArray(forKey: key) else { return items }
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let ordered = savedOrder.compactMap { lookup[$0] }
        let remaining = items.filter { !savedOrder.contains($0.id) }
        return ordered + remaining
    }
}
