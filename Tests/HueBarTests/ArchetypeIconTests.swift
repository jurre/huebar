import Testing
@testable import HueBar

struct ArchetypeIconTests {
    @Test func knownArchetypes() {
        #expect(ArchetypeIcon.systemName(for: "living_room") == "sofa.fill")
        #expect(ArchetypeIcon.systemName(for: "bedroom") == "bed.double.fill")
        #expect(ArchetypeIcon.systemName(for: "kitchen") == "refrigerator.fill")
        #expect(ArchetypeIcon.systemName(for: "bathroom") == "shower.fill")
        #expect(ArchetypeIcon.systemName(for: "office") == "desktopcomputer")
        #expect(ArchetypeIcon.systemName(for: "dining") == "fork.knife")
        #expect(ArchetypeIcon.systemName(for: "hallway") == "figure.walk")
        #expect(ArchetypeIcon.systemName(for: "garden") == "leaf.fill")
    }

    @Test func unknownArchetypeFallback() {
        #expect(ArchetypeIcon.systemName(for: "unknown_type") == "lightbulb.fill")
        #expect(ArchetypeIcon.systemName(for: nil) == "lightbulb.fill")
    }
}
