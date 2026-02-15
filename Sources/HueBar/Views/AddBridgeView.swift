import SwiftUI

/// Inline view for pairing a new bridge, shown within Settings.
struct AddBridgeView: View {
    @Bindable var bridgeManager: BridgeManager
    var onDone: () -> Void

    @State private var discovery = HueBridgeDiscovery()
    @State private var authService = HueAuthService(checkStoredCredentials: false)
    @State private var manualIP = ""

    /// Bridges already known — don't show them as discoverable
    private var newBridges: [DiscoveredBridge] {
        let knownIPs = Set(bridgeManager.bridges.map(\.client.bridgeIP))
        return discovery.discoveredBridges.filter { !knownIPs.contains($0.ip) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDone) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)

                Text("Add Bridge")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    switch authService.authState {
                    case .waitingForLinkButton:
                        linkButtonSection
                    case .authenticated:
                        pairedSection
                    case .error(let message):
                        errorSection(message: message)
                    default:
                        discoverySection
                    }
                }
                .padding()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            discovery.addCachedBridge()
            discovery.startDiscovery()
        }
        .onChange(of: authService.authState) { _, newState in
            if case .authenticated = newState, let creds = authService.lastPairedCredentials {
                bridgeManager.addBridge(credentials: creds)
                if let connection = bridgeManager.bridge(for: creds.id) {
                    Task { await connection.connect() }
                }
            }
        }
    }

    // MARK: - Discovery

    private var discoverySection: some View {
        VStack(spacing: 12) {
            if discovery.isSearching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching for bridges…")
                        .foregroundStyle(.secondary)
                }
            }

            if newBridges.isEmpty && !discovery.isSearching {
                Text("No new bridges found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(newBridges) { bridge in
                Button {
                    authService.authenticate(bridge: bridge)
                } label: {
                    HStack {
                        Image(systemName: "lightbulb.led.wide")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bridge.name).fontWeight(.medium)
                            Text(bridge.ip).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button("Search Again") {
                discovery.startDiscovery()
            }
            .disabled(discovery.isSearching)

            Divider()

            VStack(spacing: 8) {
                Text("Or enter bridge IP manually")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    TextField("IP address", text: $manualIP)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { connectManual() }
                    Button("Connect") { connectManual() }
                        .disabled(!IPValidation.isValidWithPort(manualIP))
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

    // MARK: - Paired

    private var pairedSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Bridge added successfully!")
                .fontWeight(.medium)

            Button("Done") { onDone() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Error

    private func errorSection(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title).foregroundStyle(.yellow)
            Text(message)
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Try Again") {
                authService.cancelAuthentication()
                discovery.startDiscovery()
            }
        }
    }

    // MARK: - Helpers

    private func connectManual() {
        let ip = manualIP.trimmingCharacters(in: .whitespaces)
        guard IPValidation.isValidWithPort(ip) else { return }
        authService.authenticate(bridgeIP: ip, bridgeId: "manual-\(ip)", bridgeName: "Hue Bridge")
    }
}
