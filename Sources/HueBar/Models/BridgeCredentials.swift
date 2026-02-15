import Foundation

struct BridgeCredentials: Codable, Identifiable, Sendable {
    let id: String          // Bridge ID (from mDNS bridgeid or pairing response)
    var bridgeIP: String    // Can change if bridge gets new IP
    let applicationKey: String
    var name: String        // User-facing name (e.g., "Office Bridge")
}
