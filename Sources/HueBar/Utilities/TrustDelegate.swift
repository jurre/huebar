import Foundation

final class HueBridgeTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let bridgeIP: String?

    init(bridgeIP: String? = nil) {
        self.bridgeIP = bridgeIP
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        // Only custom-validate for the known bridge IP
        let host = challenge.protectionSpace.host
        guard let bridgeIP, host == bridgeIP else {
            return (.performDefaultHandling, nil)
        }

        // Validate against the Hue root CAs — fail closed if configuration fails,
        // otherwise SecTrust falls back to system CAs and any public cert would pass.
        guard SecTrustSetAnchorCertificates(serverTrust, SignifyRootCA.certificates as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(serverTrust, true) == errSecSuccess
        else {
            return (.cancelAuthenticationChallenge, nil)
        }

        // Use basic X.509 policy (no hostname check) — the bridge cert's CN
        // is the bridge ID (e.g. "ECB5FAFFFE123456"), not the IP address.
        SecTrustSetPolicies(serverTrust, SecPolicyCreateBasicX509())

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        if isValid {
            return (.useCredential, URLCredential(trust: serverTrust))
        } else {
            return (.cancelAuthenticationChallenge, nil)
        }
        }
    }
}
