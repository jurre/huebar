import Network
import Testing

@testable import HueBar

struct HueBridgeDiscoveryTests {
    @Test func resolutionParametersForceIPv4() throws {
        let parameters = HueBridgeDiscovery.resolutionParameters()
        let ipOptions = try #require(
            parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options
        )
        #expect(ipOptions.version == .v4)
    }

    @Test func hostStringDropsInterface() throws {
        let scoped = try #require(IPv4Address("192.168.1.39%lo0"))
        #expect(scoped.interface != nil)
        #expect(HueBridgeDiscovery.hostString(for: scoped) == "192.168.1.39")
    }

    @Test func hostStringPlainAddress() throws {
        let plain = try #require(IPv4Address("192.168.1.39"))
        #expect(HueBridgeDiscovery.hostString(for: plain) == "192.168.1.39")
    }
}
