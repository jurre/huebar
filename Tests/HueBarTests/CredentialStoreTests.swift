import Foundation
import Security
import Testing

@testable import HueBar

@Suite(.serialized) @MainActor
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
        try CredentialStore.saveBridge(BridgeCredentials( id: "b1", bridgeIP: "192.168.1.10", applicationKey: "test-key-123", name: "Hue Bridge"))
        let loaded = CredentialStore.loadBridges()
        #expect(loaded.count == 1)
        #expect(loaded[0].bridgeIP == "192.168.1.10")
        #expect(loaded[0].applicationKey == "test-key-123")
    }

    @Test func loadWhenEmpty() {
        defer { CredentialStore.delete() }
        CredentialStore.delete()
        #expect(CredentialStore.loadBridges().isEmpty)
    }

    @Test func delete() throws {
        defer { CredentialStore.delete(); cleanLastBridgeIP() }
        try CredentialStore.saveBridge(BridgeCredentials(id: "b1", bridgeIP: "192.168.1.10", applicationKey: "key", name: "Hue Bridge"))
        CredentialStore.delete()
        #expect(CredentialStore.loadBridges().isEmpty)
    }

    @Test func overwrite() throws {
        defer { CredentialStore.delete(); cleanLastBridgeIP() }
        try CredentialStore.saveBridge(BridgeCredentials(id: "same-id", bridgeIP: "192.168.1.10", applicationKey: "first", name: "Hue Bridge"))
        try CredentialStore.saveBridge(BridgeCredentials(id: "same-id", bridgeIP: "192.168.1.20", applicationKey: "second", name: "Hue Bridge"))
        let loaded = CredentialStore.loadBridges()
        #expect(loaded.count == 1)
        #expect(loaded[0].bridgeIP == "192.168.1.20")
        #expect(loaded[0].applicationKey == "second")
    }

    @Test func deleteWhenNothingStored() {
        CredentialStore.delete()
        CredentialStore.delete()
        #expect(CredentialStore.loadBridges().isEmpty)
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
        try CredentialStore.saveBridge(BridgeCredentials(id: "b1", bridgeIP: "10.0.0.5", applicationKey: "key-abc", name: "Hue Bridge"))
        #expect(CredentialStore.loadLastBridgeIP() == "10.0.0.5")

        CredentialStore.delete()
        #expect(CredentialStore.loadBridges().isEmpty)
        #expect(CredentialStore.loadLastBridgeIP() == "10.0.0.5")
    }

    @Test func saveCredentialsAlsoSavesLastBridgeIP() throws {
        cleanLastBridgeIP()
        defer {
            CredentialStore.delete()
            cleanLastBridgeIP()
        }
        try CredentialStore.saveBridge(BridgeCredentials(id: "b1", bridgeIP: "172.16.0.1", applicationKey: "key-xyz", name: "Hue Bridge"))
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

    // MARK: - Bridge Discovery Dedup

    @Test @MainActor func manualBridgeSameIPNotDuplicated() {
        let discovery = HueBridgeDiscovery()
        let first = discovery.addManualBridge(ip: "192.168.1.50")
        let second = discovery.addManualBridge(ip: "192.168.1.50")

        #expect(discovery.discoveredBridges.count == 1)
        #expect(discovery.discoveredBridges.first?.ip == "192.168.1.50")
        #expect(first.ip == second.ip)
    }

    @Test @MainActor func manualBridgesDifferentIPsBothAdded() {
        let discovery = HueBridgeDiscovery()
        _ = discovery.addManualBridge(ip: "192.168.1.50")
        _ = discovery.addManualBridge(ip: "192.168.1.51")

        #expect(discovery.discoveredBridges.count == 2)
        let ips = Set(discovery.discoveredBridges.map(\.ip))
        #expect(ips == ["192.168.1.50", "192.168.1.51"])
    }

    @Test @MainActor func cachedBridgeNotDuplicatedWhenManualExists() throws {
        cleanLastBridgeIP()
        defer { cleanLastBridgeIP() }
        try CredentialStore.saveLastBridgeIP("10.0.0.5")
        let discovery = HueBridgeDiscovery()
        _ = discovery.addManualBridge(ip: "10.0.0.5")

        discovery.addCachedBridge()

        #expect(discovery.discoveredBridges.count == 1)
        #expect(discovery.discoveredBridges.first?.ip == "10.0.0.5")
    }

    @Test @MainActor func cachedBridgeAddedWhenNoDuplicate() throws {
        cleanLastBridgeIP()
        defer { cleanLastBridgeIP() }
        try CredentialStore.saveLastBridgeIP("10.0.0.5")
        let discovery = HueBridgeDiscovery()
        _ = discovery.addManualBridge(ip: "192.168.1.1")

        discovery.addCachedBridge()

        #expect(discovery.discoveredBridges.count == 2)
        let ips = Set(discovery.discoveredBridges.map(\.ip))
        #expect(ips == ["192.168.1.1", "10.0.0.5"])
    }

    @Test @MainActor func cachedBridgeCalledTwiceNotDuplicated() throws {
        cleanLastBridgeIP()
        defer { cleanLastBridgeIP() }
        try CredentialStore.saveLastBridgeIP("10.0.0.5")

        let discovery = HueBridgeDiscovery()
        discovery.addCachedBridge()
        discovery.addCachedBridge()

        #expect(discovery.discoveredBridges.count == 1)
    }
}

@Suite
struct HueBridgeRootCATests {
    @Test func hueBridgeRootCADecodes() {
        let certs = HueBridgeRootCA.certificates
        #expect(certs.count == 2)

        let oldSummary = SecCertificateCopySubjectSummary(certs[0]) as String?
        #expect(oldSummary == "root-bridge")

        let newSummary = SecCertificateCopySubjectSummary(certs[1]) as String?
        #expect(newSummary == "Hue Root CA 01")
    }
}
