import AppKit
import Foundation
import Testing

@testable import HueBar

@Suite(.serialized) @MainActor
struct SleepWakeManagerTests {
    @Test("Sleep turns off configured rooms and zones on both bridges")
    func sleepAcrossBridges() async throws {
        let context = makeContext(on: true)
        defer { context.manager.stopObserving() }
        context.manager.configs = context.targets.map { config(for: $0, mode: .sleepOnly) }

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await waitForRequests(context.server, count: 4)

        #expect(context.server.writes == Set(context.targets.map {
            "bridge-\($0.bridge)/grouped_light/\($0.light)/off"
        }))
        #expect(context.bridges.bridges.allSatisfy { $0.client.groupedLights.allSatisfy { !$0.isOn } })
    }

    @Test("Wake turns on configured rooms and zones on both bridges")
    func wakeAcrossBridges() async throws {
        let context = makeContext(on: false)
        defer { context.manager.stopObserving() }
        context.manager.configs = context.targets.map { config(for: $0, mode: .wakeOnly) }

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitForRequests(context.server, count: 4)

        #expect(context.server.writes == Set(context.targets.map {
            "bridge-\($0.bridge)/grouped_light/\($0.light)/on"
        }))
        #expect(context.bridges.bridges.allSatisfy { $0.client.groupedLights.allSatisfy(\.isOn) })
    }

    @Test("Wake recalls a scene through the bridge owning the target")
    func wakeSceneOnOwningBridge() async throws {
        let context = makeContext(on: false)
        defer { context.manager.stopObserving() }
        let target = context.targets[3]
        context.manager.configs = [config(for: target, mode: .both, scene: target.scene)]

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitForRequests(context.server, count: 1)

        #expect(context.server.writes == ["bridge-2/scene/\(target.scene)/recall"])
        #expect(context.bridges.bridges[1].client.activeSceneId == target.scene)
        #expect(context.bridges.bridges[0].client.activeSceneId == nil)
    }

    @Test("Sleep ignores wake-only rules and lights already off")
    func sleepRespectsModeAndState() async throws {
        let context = makeContext(on: false)
        defer { context.manager.stopObserving() }
        let first = context.targets[0]
        let second = context.targets[2]
        context.bridges.bridges[0].client.groupedLights[0].on = OnState(on: true)
        context.manager.configs = [
            config(for: first, mode: .wakeOnly),
            config(for: second, mode: .sleepOnly),
        ]

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(context.server.writes.isEmpty)
        #expect(context.bridges.bridges[0].client.groupedLights[0].isOn)
    }

    @Test("A failed sleep action does not prevent other bridges from switching off")
    func sleepContinuesAfterFailure() async throws {
        let context = makeContext(on: true)
        defer { context.manager.stopObserving() }
        context.server.failWrites(on: "bridge-1")
        context.manager.configs = context.targets.map { config(for: $0, mode: .both) }

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await waitForRequests(context.server, count: 4)

        #expect(context.server.writes.count == 4)
        #expect(context.bridges.bridges[1].client.groupedLights.allSatisfy { !$0.isOn })
    }

    @Test("Missing targets do not send a wake scene to an unrelated bridge")
    func missingWakeTarget() async throws {
        let context = makeContext(on: false)
        defer { context.manager.stopObserving() }
        context.manager.configs = [SleepWakeConfig(
            targetType: .room, targetId: UUID().uuidString, targetName: "Removed room",
            mode: .wakeOnly, wakeSceneId: context.targets[0].scene, wakeSceneName: "Morning"
        )]

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(2200))

        #expect(context.server.writes.isEmpty)
        #expect(context.bridges.bridges.allSatisfy { $0.client.activeSceneId == nil })
    }

    private struct Target {
        let bridge: Int
        let type: HotkeyBinding.TargetType
        let id: String
        let light: String
        let scene: String
    }

    private func config(for target: Target, mode: SleepWakeMode, scene: String? = nil) -> SleepWakeConfig {
        SleepWakeConfig(
            targetType: target.type, targetId: target.id, targetName: "Target",
            mode: mode, wakeSceneId: scene, wakeSceneName: scene == nil ? nil : "Morning"
        )
    }

    private func makeContext(on: Bool) -> (
        manager: SleepWakeManager, bridges: BridgeManager, server: SleepWakeServer, targets: [Target]
    ) {
        let server = SleepWakeServer()
        SleepWakeURLProtocol.server = server
        var bridges: [BridgeConnection] = []
        var targets: [Target] = []
        for bridge in 1...2 {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SleepWakeURLProtocol.self]
            let client = HueAPIClient(
                bridgeIP: "127.0.0.1", applicationKey: "bridge-\(bridge)",
                session: URLSession(configuration: configuration)
            )
            for type in [HotkeyBinding.TargetType.room, .zone] {
                let target = Target(
                    bridge: bridge, type: type, id: UUID().uuidString,
                    light: UUID().uuidString, scene: UUID().uuidString
                )
                targets.append(target)
                let metadata = GroupMetadata(name: "Target", archetype: "office")
                let services = [ResourceLink(rid: target.light, rtype: "grouped_light")]
                switch type {
                case .room:
                    client.rooms.append(Room(id: target.id, metadata: metadata, services: services, children: []))
                case .zone:
                    client.zones.append(Zone(id: target.id, metadata: metadata, services: services, children: []))
                }
                client.groupedLights.append(GroupedLight(
                    id: target.light, on: OnState(on: on), dimming: nil, colorTemperature: nil
                ))
            }
            bridges.append(BridgeConnection(id: "bridge-\(bridge)", name: "Bridge \(bridge)", client: client))
        }
        let bridgeManager = BridgeManager(bridges: bridges)
        let manager = SleepWakeManager()
        manager.configure(bridgeManager: bridgeManager)
        return (manager, bridgeManager, server, targets)
    }

    private func waitForRequests(_ server: SleepWakeServer, count: Int) async {
        for _ in 0..<350 {
            if server.writes.count >= count { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class SleepWakeServer: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedWrites: Set<String> = []
    private var failingBridge: String?

    func failWrites(on bridge: String) {
        lock.lock()
        defer { lock.unlock() }
        failingBridge = bridge
    }

    var writes: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return recordedWrites
    }

    func respond(to request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        if request.httpMethod == "PUT" {
            let resource = url.path.replacingOccurrences(of: "/clip/v2/resource/", with: "")
            let action: String
            if resource.hasPrefix("scene/") {
                action = "recall"
            } else {
                let stream = try #require(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = stream.read(&buffer, maxLength: buffer.count)
                let body = try JSONSerialization.jsonObject(with: Data(buffer.prefix(max(0, count)))) as? [String: Any]
                let on = (body?["on"] as? [String: Bool])?["on"]
                action = try #require(on as Bool?) ? "on" : "off"
            }
            let bridge = try #require(request.value(forHTTPHeaderField: "hue-application-key"))
            lock.lock()
            recordedWrites.insert("\(bridge)/\(resource)/\(action)")
            let shouldFail = failingBridge == bridge
            lock.unlock()
            if shouldFail { throw URLError(.cannotConnectToHost) }
        }
        return (response, Data(#"{"errors":[],"data":[]}"#.utf8))
    }
}

private final class SleepWakeURLProtocol: URLProtocol, @unchecked Sendable {
    private static let serverLock = NSLock()
    // SAFETY: Reads from URLSession threads and writes from the main actor
    // are serialized by serverLock through the server accessor.
    nonisolated(unsafe) private static var storedServer: SleepWakeServer?

    static var server: SleepWakeServer? {
        get { serverLock.withLock { storedServer } }
        set { serverLock.withLock { storedServer = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let server = try #require(Self.server)
            let (response, data) = try server.respond(to: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
