import Foundation
import Testing

@testable import HueBar

// Extension of the serialized CredentialStoreTests suite so bridge tests
// share the same serialization and storageDirectory lifecycle.
extension CredentialStoreTests {
    private func cleanBridges() {
        try? FileManager.default.removeItem(
            at: CredentialStore.storageDirectory.appendingPathComponent("bridges.json"))
    }

    private var bridgesFile: URL {
        CredentialStore.storageDirectory.appendingPathComponent("bridges.json")
    }

    private var legacyCredentialsFile: URL {
        CredentialStore.storageDirectory.appendingPathComponent("credentials.json")
    }

    // MARK: - Multi-bridge credential tests

    @Test func saveBridgeAndLoad() throws {
        defer { cleanBridges() }
        let bridge = BridgeCredentials(
            id: "abc123", bridgeIP: "192.168.1.10", applicationKey: "key-1", name: "Office")
        try CredentialStore.saveBridge(bridge)

        let loaded = CredentialStore.loadBridges()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "abc123")
        #expect(loaded[0].bridgeIP == "192.168.1.10")
        #expect(loaded[0].applicationKey == "key-1")
        #expect(loaded[0].name == "Office")
    }

    @Test func saveMultipleBridges() throws {
        defer { cleanBridges() }
        try CredentialStore.saveBridge(
            BridgeCredentials(
                id: "b1", bridgeIP: "10.0.0.1", applicationKey: "k1", name: "Living Room"))
        try CredentialStore.saveBridge(
            BridgeCredentials(
                id: "b2", bridgeIP: "10.0.0.2", applicationKey: "k2", name: "Bedroom"))

        let loaded = CredentialStore.loadBridges()
        #expect(loaded.count == 2)
        let ids = Set(loaded.map(\.id))
        #expect(ids == ["b1", "b2"])
    }

    @Test func saveBridgeUpdatesExisting() throws {
        defer { cleanBridges() }
        try CredentialStore.saveBridge(
            BridgeCredentials(
                id: "same-id", bridgeIP: "192.168.1.1", applicationKey: "key", name: "Bridge"))
        try CredentialStore.saveBridge(
            BridgeCredentials(
                id: "same-id", bridgeIP: "192.168.1.99", applicationKey: "key", name: "Bridge"))

        let loaded = CredentialStore.loadBridges()
        #expect(loaded.count == 1)
        #expect(loaded[0].bridgeIP == "192.168.1.99")
    }

    @Test func removeBridge() throws {
        defer { cleanBridges() }
        try CredentialStore.saveBridge(
            BridgeCredentials(id: "keep", bridgeIP: "10.0.0.1", applicationKey: "k1", name: "A"))
        try CredentialStore.saveBridge(
            BridgeCredentials(id: "drop", bridgeIP: "10.0.0.2", applicationKey: "k2", name: "B"))

        try CredentialStore.removeBridge(id: "drop")

        let loaded = CredentialStore.loadBridges()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "keep")
    }

    @Test func removeNonexistentBridgeIsNoop() throws {
        defer { cleanBridges() }
        try CredentialStore.saveBridge(
            BridgeCredentials(
                id: "exists", bridgeIP: "10.0.0.1", applicationKey: "k1", name: "Bridge"))

        try CredentialStore.removeBridge(id: "no-such-id")

        let loaded = CredentialStore.loadBridges()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "exists")
    }

    @Test func migrationFromSingleCredentials() throws {
        defer { cleanBridges(); CredentialStore.delete() }
        // Write a legacy credentials.json with the old Credentials format
        try FileManager.default.createDirectory(
            at: CredentialStore.storageDirectory, withIntermediateDirectories: true)
        let legacy = CredentialStore.Credentials(bridgeIP: "172.16.0.5", applicationKey: "old-key")
        let data = try JSONEncoder().encode(legacy)
        try data.write(to: legacyCredentialsFile)

        let loaded = CredentialStore.loadBridges()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "migrated-172.16.0.5")
        #expect(loaded[0].bridgeIP == "172.16.0.5")
        #expect(loaded[0].applicationKey == "old-key")
        #expect(loaded[0].name == "Hue Bridge")

        // Legacy file should be deleted after migration
        #expect(!FileManager.default.fileExists(atPath: legacyCredentialsFile.path))
    }

    @Test func filePermissions() throws {
        defer { cleanBridges() }
        try CredentialStore.saveBridge(
            BridgeCredentials(id: "perm", bridgeIP: "10.0.0.1", applicationKey: "k", name: "B"))

        let attrs = try FileManager.default.attributesOfItem(atPath: bridgesFile.path)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0
        #expect(perms == 0o600)
    }
}
