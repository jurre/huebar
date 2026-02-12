import Foundation
import Network
import SwiftUI
import os

struct DiscoveredBridge: Identifiable, Hashable {
    let id: String
    let ip: String
    let name: String
}

@Observable
@MainActor
final class HueBridgeDiscovery {
    private static let logger = Logger(subsystem: "com.huebar", category: "discovery")

    var discoveredBridges: [DiscoveredBridge] = []
    var isSearching: Bool = false
    var manualIP: String = ""
    var discoveryError: String?

    private var browser: NWBrowser?
    private var stopTask: Task<Void, Never>?
    private var cloudDiscoveryTask: Task<Void, Never>?
    private var pendingResolutions: Int = 0

    func startDiscovery() {
        Self.logger.info("Starting bridge discovery")
        discoveredBridges = []
        discoveryError = nil
        isSearching = true

        // Try both mDNS and cloud discovery in parallel
        startMDNSDiscovery()
        cloudDiscoveryTask = Task { await cloudDiscover() }

        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            // If resolutions are still in-flight and no bridges found, wait longer
            if let self, self.pendingResolutions > 0, self.discoveredBridges.isEmpty {
                for _ in 0..<10 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    if self.pendingResolutions <= 0 || !self.discoveredBridges.isEmpty {
                        break
                    }
                }
            }
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
                case .ready:
                    Self.logger.debug("mDNS browser state: ready")
                case .failed(let error):
                    Self.logger.warning("mDNS browser failed: \(error.localizedDescription)")
                    self.stopDiscovery()
                case .waiting(let error):
                    Self.logger.debug("mDNS browser waiting: \(error.localizedDescription)")
                case .cancelled:
                    Self.logger.debug("mDNS browser cancelled")
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
    /// Retries up to 3 times with exponential backoff (2s, 4s, 8s).
    private func cloudDiscover() async {
        guard let url = URL(string: "https://discovery.meethue.com") else { return }
        let maxRetries = 3
        let baseDelay: UInt64 = 2

        for attempt in 0...maxRetries {
            guard !Task.isCancelled else { return }

            if attempt > 0 {
                Self.logger.info("Cloud discovery retry \(attempt + 1)/\(maxRetries + 1)")
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse else { return }
                Self.logger.info("Cloud discovery status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 429 {
                    Self.logger.warning("Cloud discovery rate limited (429)")
                    let retryAfter = retryAfterDelay(from: httpResponse, fallback: baseDelay << attempt)
                    discoveryError = "Cloud service rate-limited, retrying… (\(attempt + 1)/\(maxRetries + 1))"
                    if attempt < maxRetries {
                        try await Task.sleep(for: .seconds(retryAfter))
                        continue
                    }
                    discoveryError = "Cloud service rate-limited after \(maxRetries + 1) attempts"
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    discoveryError = "Cloud discovery unavailable (HTTP \(httpResponse.statusCode))"
                    return
                }

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
                if !bridges.isEmpty { discoveryError = nil }
                return
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Cloud discovery failed: \(error.localizedDescription)")
                if attempt < maxRetries {
                    discoveryError = "Cloud discovery failed, retrying… (\(attempt + 1)/\(maxRetries + 1))"
                    try? await Task.sleep(for: .seconds(baseDelay << attempt))
                } else {
                    discoveryError = "Cloud discovery failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Extracts Retry-After header delay (capped at 30s), or returns the fallback.
    private nonisolated func retryAfterDelay(from response: HTTPURLResponse, fallback: UInt64) -> UInt64 {
        if let value = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = UInt64(value) {
            return min(seconds, 30)
        }
        return min(fallback, 30)
    }

    func stopDiscovery() {
        Self.logger.info("Stopping discovery — found \(self.discoveredBridges.count) bridge(s)")
        stopTask?.cancel()
        stopTask = nil
        cloudDiscoveryTask?.cancel()
        cloudDiscoveryTask = nil
        browser?.cancel()
        browser = nil
        pendingResolutions = 0
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

    /// Pre-populate a bridge from the last known IP (survives credential deletion).
    func addCachedBridge() {
        guard let ip = CredentialStore.loadLastBridgeIP(),
              IPValidation.isValid(ip) else { return }
        let bridge = DiscoveredBridge(
            id: "cached-\(ip)",
            ip: ip,
            name: "Hue Bridge (cached)"
        )
        if !discoveredBridges.contains(where: { $0.ip == ip }) {
            discoveredBridges.append(bridge)
        }
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

        Self.logger.info("Bridge found via mDNS: \(bridgeID)")
        resolveEndpoint(result.endpoint, bridgeID: bridgeID, name: name)
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint, bridgeID: String, name: String) {
        pendingResolutions += 1
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.pendingResolutions -= 1
                    if let ip = self.extractIP(from: connection) {
                        Self.logger.info("Resolved \(bridgeID) to \(ip)")
                        let bridge = DiscoveredBridge(id: bridgeID, ip: ip, name: name)
                        if !self.discoveredBridges.contains(where: { $0.id == bridgeID }) {
                            self.discoveredBridges.append(bridge)
                        }
                    }
                    connection.cancel()
                case .failed(let error):
                    self.pendingResolutions -= 1
                    Self.logger.warning("Failed to resolve \(bridgeID): \(error.localizedDescription)")
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
