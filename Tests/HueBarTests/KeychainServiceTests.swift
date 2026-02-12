import Testing

@testable import HueBar

@Suite(.serialized)
struct CredentialStoreTests {
    @Test func saveAndLoad() throws {
        defer { CredentialStore.delete() }
        try CredentialStore.save(credentials: .init(bridgeIP: "192.168.1.10", applicationKey: "test-key-123"))
        let loaded = CredentialStore.load()
        #expect(loaded?.bridgeIP == "192.168.1.10")
        #expect(loaded?.applicationKey == "test-key-123")
    }

    @Test func loadWhenEmpty() {
        defer { CredentialStore.delete() }
        CredentialStore.delete()
        #expect(CredentialStore.load() == nil)
    }

    @Test func delete() throws {
        defer { CredentialStore.delete() }
        try CredentialStore.save(credentials: .init(bridgeIP: "192.168.1.10", applicationKey: "key"))
        CredentialStore.delete()
        #expect(CredentialStore.load() == nil)
    }

    @Test func overwrite() throws {
        defer { CredentialStore.delete() }
        try CredentialStore.save(credentials: .init(bridgeIP: "192.168.1.10", applicationKey: "first"))
        try CredentialStore.save(credentials: .init(bridgeIP: "192.168.1.20", applicationKey: "second"))
        let loaded = CredentialStore.load()
        #expect(loaded?.bridgeIP == "192.168.1.20")
        #expect(loaded?.applicationKey == "second")
    }

    @Test func deleteWhenNothingStored() {
        CredentialStore.delete()
        CredentialStore.delete()
    }
}
