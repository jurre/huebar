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

    private func cleanLastBridgeIP() {
        try? FileManager.default.removeItem(
            at: CredentialStore.storageDirectory.appendingPathComponent("last_bridge_ip")
        )
    }

    @Test func saveAndLoad() throws {
        defer { CredentialStore.delete(); cleanLastBridgeIP() }
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
        defer { CredentialStore.delete(); cleanLastBridgeIP() }
        try CredentialStore.save(credentials: .init(bridgeIP: "192.168.1.10", applicationKey: "key"))
        CredentialStore.delete()
        #expect(CredentialStore.load() == nil)
    }

    @Test func overwrite() throws {
        defer { CredentialStore.delete(); cleanLastBridgeIP() }
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
        defer { CredentialStore.delete(); cleanLastBridgeIP() }
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

    // MARK: - Last Bridge IP

    @Test func saveAndLoadLastBridgeIP() throws {
        cleanLastBridgeIP()
        defer { cleanLastBridgeIP() }
        try CredentialStore.saveLastBridgeIP("192.168.1.42")
        #expect(CredentialStore.loadLastBridgeIP() == "192.168.1.42")
    }

    @Test func lastBridgeIPSurvivesCredentialDeletion() throws {
        cleanLastBridgeIP()
        defer {
            CredentialStore.delete()
            cleanLastBridgeIP()
        }
        try CredentialStore.save(credentials: .init(bridgeIP: "10.0.0.5", applicationKey: "key-abc"))
        #expect(CredentialStore.loadLastBridgeIP() == "10.0.0.5")

        CredentialStore.delete()
        #expect(CredentialStore.load() == nil)
        #expect(CredentialStore.loadLastBridgeIP() == "10.0.0.5")
    }

    @Test func saveCredentialsAlsoSavesLastBridgeIP() throws {
        cleanLastBridgeIP()
        defer {
            CredentialStore.delete()
            cleanLastBridgeIP()
        }
        try CredentialStore.save(credentials: .init(bridgeIP: "172.16.0.1", applicationKey: "key-xyz"))
        #expect(CredentialStore.loadLastBridgeIP() == "172.16.0.1")
    }

    @Test @MainActor func addCachedBridgeWithValidIP() throws {
        cleanLastBridgeIP()
        defer { cleanLastBridgeIP() }
        try CredentialStore.saveLastBridgeIP("192.168.1.100")

        let discovery = HueBridgeDiscovery()
        discovery.addCachedBridge()

        #expect(discovery.discoveredBridges.count == 1)
        #expect(discovery.discoveredBridges.first?.ip == "192.168.1.100")
        #expect(discovery.discoveredBridges.first?.name == "Hue Bridge (cached)")
    }

    @Test @MainActor func addCachedBridgeWithNoSavedIP() {
        cleanLastBridgeIP()

        let discovery = HueBridgeDiscovery()
        discovery.addCachedBridge()

        #expect(discovery.discoveredBridges.isEmpty)
    }
}
