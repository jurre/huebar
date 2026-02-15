import Foundation
import Testing

@testable import HueBar

@Suite(.serialized) @MainActor
struct HueBridgeDiscoveryTests {
    let discovery = HueBridgeDiscovery()

    init() {
        // Use a unique temp directory so tests don't conflict with CredentialStoreTests
        CredentialStore.storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HueBarDiscoveryTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        cleanLastBridgeIP()
    }

    private func cleanLastBridgeIP() {
        try? FileManager.default.removeItem(
            at: CredentialStore.storageDirectory.appendingPathComponent("last_bridge_ip")
        )
    }

    // MARK: - addManualBridge dedup

    @Test func manualBridgeSameIPNotDuplicated() {
        let first = discovery.addManualBridge(ip: "192.168.1.50")
        let second = discovery.addManualBridge(ip: "192.168.1.50")

        #expect(discovery.discoveredBridges.count == 1)
        #expect(discovery.discoveredBridges.first?.ip == "192.168.1.50")
        // Both calls return a bridge, but only one is stored
        #expect(first.ip == second.ip)
    }

    @Test func manualBridgesDifferentIPsBothAdded() {
        _ = discovery.addManualBridge(ip: "192.168.1.50")
        _ = discovery.addManualBridge(ip: "192.168.1.51")

        #expect(discovery.discoveredBridges.count == 2)
        let ips = Set(discovery.discoveredBridges.map(\.ip))
        #expect(ips == ["192.168.1.50", "192.168.1.51"])
    }

    // MARK: - addCachedBridge dedup

    @Test func cachedBridgeNotDuplicatedWhenManualExists() throws {
        defer { cleanLastBridgeIP() }
        try CredentialStore.saveLastBridgeIP("10.0.0.5")
        _ = discovery.addManualBridge(ip: "10.0.0.5")

        discovery.addCachedBridge()

        #expect(discovery.discoveredBridges.count == 1)
        #expect(discovery.discoveredBridges.first?.ip == "10.0.0.5")
    }

    @Test func cachedBridgeAddedWhenNoDuplicate() throws {
        defer { cleanLastBridgeIP() }
        try CredentialStore.saveLastBridgeIP("10.0.0.5")
        _ = discovery.addManualBridge(ip: "192.168.1.1")

        discovery.addCachedBridge()

        #expect(discovery.discoveredBridges.count == 2)
        let ips = Set(discovery.discoveredBridges.map(\.ip))
        #expect(ips == ["192.168.1.1", "10.0.0.5"])
    }

    @Test func cachedBridgeCalledTwiceNotDuplicated() throws {
        defer { cleanLastBridgeIP() }
        try CredentialStore.saveLastBridgeIP("10.0.0.5")

        discovery.addCachedBridge()
        discovery.addCachedBridge()

        #expect(discovery.discoveredBridges.count == 1)
    }
}
