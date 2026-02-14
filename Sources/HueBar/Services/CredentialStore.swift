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

    struct Credentials: Codable {
        var bridgeIP: String
        var applicationKey: String
        var certificateHash: String?
    }

    static func save(credentials: Credentials) throws {
        try ensureStorageDirectory()
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: credentialsFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsFile.path)
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
        try data.write(to: certHashFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: certHashFile.path)

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
        try data.write(to: lastBridgeIPFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lastBridgeIPFile.path)
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
