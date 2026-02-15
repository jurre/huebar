import Foundation

enum IPValidation {
    /// Validates that a string is a pure IPv4 or IPv6 address (no hostnames, paths, or ports)
    static func isValid(_ ip: String) -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        var addr4 = in_addr()
        var addr6 = in6_addr()
        return inet_pton(AF_INET, trimmed, &addr4) == 1
            || inet_pton(AF_INET6, trimmed, &addr6) == 1
    }

    /// Validates an IP or IP:port string (e.g. "192.168.1.10" or "127.0.0.1:8080")
    static func isValidWithPort(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        if isValid(trimmed) { return true }
        // Check for host:port format
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        if parts.count == 2, let port = UInt16(parts[1]), port > 0 {
            return isValid(String(parts[0]))
        }
        return false
    }
}
