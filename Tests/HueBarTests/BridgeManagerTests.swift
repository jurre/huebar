import Foundation
import Testing

@testable import HueBar

// Extension of CredentialStoreTests so bridge manager tests share
// the same serialized suite and storageDirectory lifecycle.
extension CredentialStoreTests {
    private func makeCredentials(id: String, ip: String = "192.168.1.10", name: String = "Bridge") -> BridgeCredentials {
        BridgeCredentials(id: id, bridgeIP: ip, applicationKey: "test-key-\(id)", name: name)
    }

    @Test func addBridgeCreatesBridge() throws {
        let manager = BridgeManager()
        manager.addBridge(credentials: makeCredentials(id: "bridge-1", name: "Office"))

        #expect(manager.bridges.count == 1)
        #expect(manager.bridges[0].id == "bridge-1")
        #expect(manager.bridges[0].name == "Office")
    }

    @Test func addDuplicateBridgeIsIgnored() throws {
        let manager = BridgeManager()
        let creds = makeCredentials(id: "dup-bridge")
        manager.addBridge(credentials: creds)
        manager.addBridge(credentials: creds)

        #expect(manager.bridges.count == 1)
    }

    @Test func removeBridgeDisconnectsAndRemoves() throws {
        defer {
            try? FileManager.default.removeItem(
                at: CredentialStore.storageDirectory.appendingPathComponent("bridges.json"))
        }
        let manager = BridgeManager()
        manager.addBridge(credentials: makeCredentials(id: "keep", ip: "192.168.1.10", name: "Keep"))
        manager.addBridge(credentials: makeCredentials(id: "drop", ip: "192.168.1.11", name: "Drop"))
        #expect(manager.bridges.count == 2)

        manager.removeBridge(id: "drop")

        #expect(manager.bridges.count == 1)
        #expect(manager.bridges[0].id == "keep")
    }

    @Test func bridgeForIdReturnsCorrectBridge() throws {
        let manager = BridgeManager()
        manager.addBridge(credentials: makeCredentials(id: "alpha", ip: "192.168.1.10", name: "Alpha"))
        manager.addBridge(credentials: makeCredentials(id: "beta", ip: "192.168.1.11", name: "Beta"))

        let found = manager.bridge(for: "beta")
        #expect(found?.id == "beta")
        #expect(found?.name == "Beta")

        #expect(manager.bridge(for: "nonexistent") == nil)
    }

    @Test func loadBridgesAndAddToManager() throws {
        defer {
            try? FileManager.default.removeItem(
                at: CredentialStore.storageDirectory.appendingPathComponent("bridges.json"))
        }
        try CredentialStore.saveBridge(makeCredentials(id: "stored-1", ip: "192.168.1.10", name: "First"))
        try CredentialStore.saveBridge(makeCredentials(id: "stored-2", ip: "192.168.1.11", name: "Second"))

        let manager = BridgeManager()
        let credentials = CredentialStore.loadBridges()
        for cred in credentials {
            manager.addBridge(credentials: cred)
        }

        #expect(manager.bridges.count == 2)
        let ids = Set(manager.bridges.map(\.id))
        #expect(ids == ["stored-1", "stored-2"])
    }
}
