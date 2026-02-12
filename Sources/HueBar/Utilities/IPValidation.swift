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
}
