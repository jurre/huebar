import Foundation
import CryptoKit

// bridgeIP is immutable (let) and String is Sendable, so this is safe.
// NSObject prevents automatic Sendable synthesis, but no mutable state exists.
final class HueBridgeTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let bridgeIP: String?

    /// Create a delegate that only bypasses TLS for the specified bridge IP.
    /// If bridgeIP is nil, performs default TLS validation (used during discovery).
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

        // Only bypass TLS validation for the known bridge IP
        let host = challenge.protectionSpace.host
        guard let bridgeIP, host == bridgeIP else {
            return (.performDefaultHandling, nil)
        }

        // Extract certificate and compute SHA-256 hash
        guard let certHash = certificateHash(from: serverTrust) else {
            return (.cancelAuthenticationChallenge, nil)
        }

        // TOFU: if we have a pinned hash, verify it matches
        if let pinnedHash = CredentialStore.pinnedCertificateHash() {
            if certHash != pinnedHash {
                // Certificate changed — possible MITM
                return (.cancelAuthenticationChallenge, nil)
            }
        } else {
            // First connection — pin the certificate
            do {
                try CredentialStore.updateCertificateHash(certHash)
            } catch {
                // Can't persist the hash — refuse the connection so we never
                // trust a certificate we won't be able to verify next time.
                return (.cancelAuthenticationChallenge, nil)
            }
        }

        let credential = URLCredential(trust: serverTrust)
        return (.useCredential, credential)
    }

    private func certificateHash(from trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let cert = chain.first else { return nil }
        let data = SecCertificateCopyData(cert) as Data
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
