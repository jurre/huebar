import Testing

@testable import HueBar

@Suite(.serialized)
struct KeychainServiceTests {
    @Test func saveAndLoad() throws {
        defer { KeychainService.delete() }
        try KeychainService.save(key: "test-key-123")
        #expect(KeychainService.load() == "test-key-123")
    }

    @Test func loadWhenEmpty() {
        defer { KeychainService.delete() }
        KeychainService.delete()
        #expect(KeychainService.load() == nil)
    }

    @Test func delete() throws {
        defer { KeychainService.delete() }
        try KeychainService.save(key: "test-key-to-delete")
        KeychainService.delete()
        #expect(KeychainService.load() == nil)
    }

    @Test func overwrite() throws {
        defer { KeychainService.delete() }
        try KeychainService.save(key: "first")
        try KeychainService.save(key: "second")
        #expect(KeychainService.load() == "second")
    }

    @Test func deleteWhenNothingStored() {
        KeychainService.delete()
        KeychainService.delete()
    }
}
