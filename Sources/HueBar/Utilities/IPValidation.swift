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

    /// Validates an IP or IP:port string (e.g. "192.168.1.10", "127.0.0.1:8080", "[::1]:8080")
    static func isValidWithPort(_ address: String) -> Bool {
        let parsed = parseHostPort(address)
        return isValid(parsed.host)
    }

    /// Parse a host string that may include a port, handling IPv6 bracket notation.
    /// Supports: "192.168.1.10", "192.168.1.10:8080", "::1", "[::1]:8080"
    static func parseHostPort(_ address: String) -> (host: String, port: Int?) {
        let trimmed = address.trimmingCharacters(in: .whitespaces)

        // Bracketed IPv6: "[2001:db8::1]" or "[2001:db8::1]:443"
        if trimmed.hasPrefix("["), let closingBracket = trimmed.firstIndex(of: "]") {
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingBracket])
            let afterBracket = trimmed.index(after: closingBracket)
            if afterBracket < trimmed.endIndex, trimmed[afterBracket] == ":" {
                let portStr = trimmed[trimmed.index(after: afterBracket)...]
                return (host: host, port: Int(portStr))
            }
            return (host: host, port: nil)
        }

        // Count colons to distinguish IPv4:port from bare IPv6
        let colonCount = trimmed.filter { $0 == ":" }.count
        if colonCount == 1 {
            // IPv4 or hostname with port: "192.168.1.10:8080"
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let port = Int(parts[1]) {
                return (host: String(parts[0]), port: port)
            }
        }

        // Bare IPv4, bare IPv6, or hostname without port
        return (host: trimmed, port: nil)
    }
}
