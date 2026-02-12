import SwiftUI

struct SetupView: View {
    @Bindable var discovery: HueBridgeDiscovery
    @Bindable var authService: HueAuthService

    @State private var manualIP: String = ""
    @State private var pulseAnimation: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Connect to Hue Bridge")
                .font(.headline)

            switch authService.authState {
            case .waitingForLinkButton:
                linkButtonSection
            case .error(let message):
                errorSection(message: message)
            default:
                discoverySection
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding()
        .frame(width: 300)
        .task {
            // Auto-connect if we have a known bridge IP from a previous session
            if let knownIP = UserDefaults.standard.string(forKey: "huebar.bridgeIP") {
                UserDefaults.standard.removeObject(forKey: "huebar.bridgeIP")
                authService.authenticate(bridgeIP: knownIP)
            } else {
                discovery.addCachedBridge()
                discovery.startDiscovery()
            }
        }
    }

    // MARK: - Discovery

    private var discoverySection: some View {
        VStack(spacing: 12) {
            if discovery.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching for bridges…")
                        .foregroundStyle(.secondary)
                }
            }

            if discovery.discoveredBridges.isEmpty && !discovery.isSearching {
                if let error = discovery.discoveryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Text("No bridges found. Check that your Mac is on the same network as your Hue Bridge, or enter the IP manually below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !discovery.discoveredBridges.isEmpty {
                VStack(spacing: 4) {
                    ForEach(discovery.discoveredBridges) { bridge in
                        Button {
                            authService.authenticate(bridgeIP: bridge.ip)
                        } label: {
                            HStack {
                                Image(systemName: "lightbulb.led.wide")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bridge.name)
                                        .fontWeight(.medium)
                                    Text(bridge.ip)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if discovery.discoveredBridges.isEmpty && !discovery.isSearching {
                Button("Search Again") {
                    discovery.startDiscovery()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Search Again") {
                    discovery.startDiscovery()
                }
                .disabled(discovery.isSearching)
            }

            Divider()

            VStack(spacing: 8) {
                Text("Or enter bridge IP manually")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("IP address", text: $manualIP)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            connectManual()
                        }

                    Button("Connect") {
                        connectManual()
                    }
                    .disabled(!IPValidation.isValid(manualIP))
                }
            }
        }
    }

    // MARK: - Link Button

    private var linkButtonSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "button.programmable")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)

            Text("Press the link button on your Hue Bridge")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                authService.cancelAuthentication()
            }
        }
    }

    // MARK: - Error

    private func errorSection(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.yellow)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Try Again") {
                authService.cancelAuthentication()
                discovery.startDiscovery()
            }
        }
    }

    // MARK: - Helpers

    private func connectManual() {
        let ip = manualIP.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        authService.authenticate(bridgeIP: ip)
    }
}
