import Foundation

/// Stores Hue Bridge credentials in ~/Library/Application Support/HueBar/
enum CredentialStore {
    // Allow tests to override the storage directory
    nonisolated(unsafe) static var storageDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("HueBar", isDirectory: true)
    }()

    private static var credentialsFile: URL {
        storageDirectory.appendingPathComponent("credentials.json")
    }

    private static var certHashFile: URL {
        storageDirectory.appendingPathComponent("cert_hash")
    }

    private static var lastBridgeIPFile: URL {
        storageDirectory.appendingPathComponent("last_bridge_ip")
    }

    private static func ensureStorageDirectory() throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// Write data to file with 0o600 permissions, avoiding the race window
    /// where `.atomic` writes create files with default (world-readable) permissions
    /// before `setAttributes` can restrict them.
    private static func writeRestricted(_ data: Data, to url: URL) throws {
        let path = url.path
        // Open (or create) the file with restricted permissions from the start
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let result = write(fd, base.advanced(by: written), buffer.count - written)
                guard result >= 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                written += result
            }
        }
    }

    struct Credentials: Codable {
        var bridgeIP: String
        var applicationKey: String
        var certificateHash: String?
    }

    static func save(credentials: Credentials) throws {
        try ensureStorageDirectory()
        let data = try JSONEncoder().encode(credentials)
        try writeRestricted(data, to: credentialsFile)
        try? saveLastBridgeIP(credentials.bridgeIP)
    }

    static func load() -> Credentials? {
        guard let data = try? Data(contentsOf: credentialsFile) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func updateCertificateHash(_ hash: String) throws {
        // Save cert hash independently so TOFU works before credentials exist
        try ensureStorageDirectory()
        let data = Data(hash.utf8)
        try writeRestricted(data, to: certHashFile)

        // Also update credentials if they exist
        if var creds = load() {
            creds.certificateHash = hash
            try save(credentials: creds)
        }
    }

    static func pinnedCertificateHash() -> String? {
        // Read from standalone file first (available before credentials exist)
        if let data = try? Data(contentsOf: certHashFile),
           let hash = String(data: data, encoding: .utf8), !hash.isEmpty {
            return hash
        }
        return load()?.certificateHash
    }

    /// Save bridge IP independently so it survives credential deletion.
    static func saveLastBridgeIP(_ ip: String) throws {
        try ensureStorageDirectory()
        let data = Data(ip.utf8)
        try writeRestricted(data, to: lastBridgeIPFile)
    }

    static func loadLastBridgeIP() -> String? {
        guard let data = try? Data(contentsOf: lastBridgeIPFile),
              let ip = String(data: data, encoding: .utf8), !ip.isEmpty else {
            return nil
        }
        return ip
    }

    static func deleteCertificateHash() {
        try? FileManager.default.removeItem(at: certHashFile)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: credentialsFile)
        deleteCertificateHash()
    }
}
