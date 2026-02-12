import Foundation
import Network
import SwiftUI

struct DiscoveredBridge: Identifiable, Hashable {
    let id: String
    let ip: String
    let name: String
}

@Observable
@MainActor
final class HueBridgeDiscovery {
    var discoveredBridges: [DiscoveredBridge] = []
    var isSearching: Bool = false
    var manualIP: String = ""

    private var browser: NWBrowser?
    private var stopTask: Task<Void, Never>?

    func startDiscovery() {
        discoveredBridges = []
        isSearching = true

        // Try both mDNS and cloud discovery in parallel
        startMDNSDiscovery()
        Task { await cloudDiscover() }

        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.stopDiscovery()
        }
    }

    private func startMDNSDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjour(type: "_hue._tcp", domain: nil),
            using: parameters
        )
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .failed:
                    self.stopDiscovery()
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                for result in results {
                    self.handleResult(result)
                }
            }
        }

        browser.start(queue: .main)
    }

    /// Fallback: discover bridges via Philips' cloud endpoint.
    /// Works even when mDNS can't cross wired/WiFi boundary.
    private func cloudDiscover() async {
        guard let url = URL(string: "https://discovery.meethue.com") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }
            let bridges = try JSONDecoder().decode([CloudDiscoveryResult].self, from: data)
            for bridge in bridges {
                let discovered = DiscoveredBridge(
                    id: bridge.id,
                    ip: bridge.internalipaddress,
                    name: "Hue Bridge (\(bridge.internalipaddress))"
                )
                if !discoveredBridges.contains(where: { $0.ip == bridge.internalipaddress }) {
                    discoveredBridges.append(discovered)
                }
            }
        } catch {
            // Cloud discovery failed — mDNS or manual entry still available
        }
    }

    func stopDiscovery() {
        stopTask?.cancel()
        stopTask = nil
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    func addManualBridge(ip: String) -> DiscoveredBridge {
        let bridge = DiscoveredBridge(
            id: "manual-\(UUID().uuidString)",
            ip: ip,
            name: "Hue Bridge (\(ip))"
        )
        if !discoveredBridges.contains(where: { $0.ip == ip }) {
            discoveredBridges.append(bridge)
        }
        return bridge
    }

    // MARK: - Private

    private func handleResult(_ result: NWBrowser.Result) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }

        let bridgeID: String
        if case let .bonjour(txtRecord) = result.metadata,
           let value = txtRecord.txtStringValue(for: "bridgeid") {
            bridgeID = value
        } else {
            bridgeID = name
        }

        guard !discoveredBridges.contains(where: { $0.id == bridgeID }) else { return }

        resolveEndpoint(result.endpoint, bridgeID: bridgeID, name: name)
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint, bridgeID: String, name: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    if let ip = self.extractIP(from: connection) {
                        let bridge = DiscoveredBridge(id: bridgeID, ip: ip, name: name)
                        if !self.discoveredBridges.contains(where: { $0.id == bridgeID }) {
                            self.discoveredBridges.append(bridge)
                        }
                    }
                    connection.cancel()
                case .failed:
                    connection.cancel()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private nonisolated func extractIP(from connection: NWConnection) -> String? {
        guard let innerEndpoint = connection.currentPath?.remoteEndpoint else { return nil }
        switch innerEndpoint {
        case let .hostPort(host, _):
            switch host {
            case let .ipv4(address):
                return "\(address)"
            case let .ipv6(address):
                return "\(address)"
            default:
                return nil
            }
        default:
            return nil
        }
    }

}

private extension NWTXTRecord {
    func txtStringValue(for key: String) -> String? {
        switch self.getEntry(for: key) {
        case let .string(value):
            return value
        default:
            return nil
        }
    }
}

private struct CloudDiscoveryResult: Decodable {
    let id: String
    let internalipaddress: String
}
