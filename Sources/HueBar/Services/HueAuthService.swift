import Foundation
import SwiftUI

enum AuthState: Sendable {
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

    private let trustDelegate = HueBridgeTrustDelegate()
    private var pollingTask: Task<Void, Never>?

    init() {
        if let key = KeychainService.load() {
            authState = .authenticated(applicationKey: key)
        }
    }

    /// Start the link-button authentication flow
    func authenticate(bridgeIP: String) {
        pollingTask?.cancel()
        self.bridgeIP = bridgeIP
        authState = .waitingForLinkButton

        let delegate = trustDelegate
        pollingTask = Task {
            let session = URLSession(
                configuration: .ephemeral,
                delegate: delegate,
                delegateQueue: nil
            )
            defer { session.invalidateAndCancel() }

            guard let url = URL(string: "https://\(bridgeIP)/api") else {
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
                        try KeychainService.save(key: success.username)
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

    /// Sign out — remove stored key
    func signOut() {
        pollingTask?.cancel()
        pollingTask = nil
        KeychainService.delete()
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
