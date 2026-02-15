import Foundation
import SwiftUI

enum AuthState: Sendable, Equatable {
    case notAuthenticated
    case waitingForLinkButton
    case authenticated(applicationKey: String)
    case error(String)
}

@Observable
@MainActor
final class HueAuthService {
    var authState: AuthState = .notAuthenticated
    private(set) var bridgeIP: String?
    /// The most recently paired bridge credentials (set after successful auth)
    private(set) var lastPairedCredentials: BridgeCredentials?

    private var pollingTask: Task<Void, Never>?

    init(checkStoredCredentials: Bool = true) {
        if checkStoredCredentials, !CredentialStore.loadBridges().isEmpty {
            // Mark as authenticated so the app knows we have stored bridges
            // The actual bridge data is loaded by BridgeManager
            authState = .authenticated(applicationKey: "stored")
        }
    }

    /// Start the link-button authentication flow for a discovered bridge
    func authenticate(bridge: DiscoveredBridge) {
        authenticate(bridgeIP: bridge.ip, bridgeId: bridge.id, bridgeName: bridge.name)
    }

    /// Start the link-button authentication flow
    func authenticate(bridgeIP: String, bridgeId: String? = nil, bridgeName: String? = nil) {
        guard IPValidation.isValidWithPort(bridgeIP) else {
            authState = .error("Invalid IP address")
            return
        }
        pollingTask?.cancel()
        self.bridgeIP = bridgeIP
        authState = .waitingForLinkButton

        let parsed = IPValidation.parseHostPort(bridgeIP)
        let isLocal = parsed.host == "127.0.0.1" || parsed.host == "localhost"

        pollingTask = Task {
            let session: URLSession
            if isLocal {
                session = URLSession(configuration: .ephemeral)
            } else {
                session = URLSession(
                    configuration: .ephemeral,
                    delegate: HueBridgeTrustDelegate(bridgeIP: parsed.host),
                    delegateQueue: nil
                )
            }
            defer { session.invalidateAndCancel() }

            var components = URLComponents()
            components.scheme = isLocal ? "http" : "https"
            components.host = parsed.host
            components.port = parsed.port
            components.path = "/api"
            guard let url = components.url else {
                authState = .error("Invalid bridge IP")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data(
                #"{"devicetype":"huebar#macos","generateclientkey":true}"#.utf8
            )
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let deadline = ContinuousClock.now + .seconds(30)

            while !Task.isCancelled && ContinuousClock.now < deadline {
                do {
                    let (data, _) = try await session.data(for: request)
                    let responses = try JSONDecoder().decode(
                        [AuthResponse].self, from: data
                    )

                    if let success = responses.first?.success {
                        let credentials = BridgeCredentials(
                            id: bridgeId ?? "bridge-\(bridgeIP)",
                            bridgeIP: bridgeIP,
                            applicationKey: success.username,
                            name: bridgeName ?? "Hue Bridge"
                        )
                        try CredentialStore.saveBridge(credentials)
                        lastPairedCredentials = credentials
                        authState = .authenticated(applicationKey: success.username)
                        return
                    }

                    // type 101 = link button not pressed; keep polling
                } catch is CancellationError {
                    return
                } catch {
                    authState = .error(error.localizedDescription)
                    return
                }

                try? await Task.sleep(for: .seconds(2))
            }

            if !Task.isCancelled {
                authState = .error(
                    "Timed out waiting for link button press"
                )
            }
        }
    }

    /// Stop polling
    func cancelAuthentication() {
        pollingTask?.cancel()
        pollingTask = nil
        authState = .notAuthenticated
    }

    /// Sign out — reset auth state (credential cleanup done by BridgeManager)
    func signOut() {
        pollingTask?.cancel()
        pollingTask = nil
        lastPairedCredentials = nil
        bridgeIP = nil
        authState = .notAuthenticated
    }

    var applicationKey: String? {
        if case .authenticated(let key) = authState {
            return key
        }
        return nil
    }

    var isAuthenticated: Bool {
        applicationKey != nil
    }

    // MARK: - Response Models

    private struct AuthResponse: Decodable {
        let success: AuthSuccess?
        let error: AuthError?
    }

    private struct AuthSuccess: Decodable {
        let username: String
        let clientkey: String?
    }

    private struct AuthError: Decodable {
        let type: Int
        let description: String
    }
}
