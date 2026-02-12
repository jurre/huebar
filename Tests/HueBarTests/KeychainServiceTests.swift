import Foundation
import Testing

@testable import HueBar

@Suite(.serialized)
struct CredentialStoreTests {
    init() {
        // Use a temp directory so tests never touch real credentials
        CredentialStore.storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HueBarTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    }

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

    @Test func certHashSavedBeforeCredentials() throws {
        defer { CredentialStore.delete() }
        // No credentials exist yet
        #expect(CredentialStore.load() == nil)
        // Cert hash can still be saved and retrieved (TOFU during initial auth)
        try CredentialStore.updateCertificateHash("abc123hash")
        #expect(CredentialStore.pinnedCertificateHash() == "abc123hash")
    }

    @Test func certHashSurvivedWithCredentials() throws {
        defer { CredentialStore.delete() }
        try CredentialStore.updateCertificateHash("abc123hash")
        try CredentialStore.save(credentials: .init(bridgeIP: "192.168.1.10", applicationKey: "key"))
        // Hash is still available after credentials are saved
        #expect(CredentialStore.pinnedCertificateHash() == "abc123hash")
    }

    @Test func deleteRemovesCertHash() throws {
        defer { CredentialStore.delete() }
        try CredentialStore.updateCertificateHash("abc123hash")
        CredentialStore.delete()
        #expect(CredentialStore.pinnedCertificateHash() == nil)
    }
}
