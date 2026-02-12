import Foundation

enum ArchetypeIcon {
    private static let mapping: [String: String] = [
        "living_room": "sofa.fill",
        "kitchen": "refrigerator.fill",
        "dining": "fork.knife",
        "bedroom": "bed.double.fill",
        "kids_bedroom": "figure.and.child.holdinghands",
        "bathroom": "shower.fill",
        "nursery": "baby.bottle.fill",
        "recreation": "gamecontroller.fill",
        "office": "desktopcomputer",
        "gym": "dumbbell.fill",
        "garage": "car.fill",
        "home": "house.fill",
        "downstairs": "arrow.down.to.line",
        "upstairs": "arrow.up.to.line",
        "top_floor": "building.2.fill",
        "attic": "triangle.fill",
        "guest_room": "person.fill",
        "staircase": "stairs",
        "toilet": "toilet.fill",
        "front_door": "door.left.hand.open",
        "back_door": "door.right.hand.open",
        "terrace": "sun.max.fill",
        "garden": "leaf.fill",
        "driveway": "road.lanes",
        "carport": "car.rear.fill",
        "walk_in_closet": "door.sliding.left.hand.open",
        "laundry_room": "washer.fill",
        "hallway": "figure.walk",
        "man_cave": "person.crop.square.fill",
        "computer": "desktopcomputer",
        "reading": "book.fill",
        "closet": "cabinet.fill",
        "storage": "archivebox.fill",
        "tv": "tv.fill",
        "studio": "paintpalette.fill",
        "music": "music.note",
        "balcony": "building.fill",
        "porch": "lamp.floor.fill",
        "bar": "wineglass.fill",
        "pool": "figure.pool.swim",
        "other": "lightbulb.fill",
    ]

    static func systemName(for archetype: String?) -> String {
        guard let archetype else { return "lightbulb.fill" }
        return mapping[archetype] ?? "lightbulb.fill"
    }
}
