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
    }

    @available(*, deprecated, message: "Use BridgeCredentials")
    static func save(credentials: Credentials) throws {
        try ensureStorageDirectory()
        let data = try JSONEncoder().encode(credentials)
        try writeRestricted(data, to: credentialsFile)
        try? saveLastBridgeIP(credentials.bridgeIP)
    }

    @available(*, deprecated, message: "Use BridgeCredentials")
    static func load() -> Credentials? {
        guard let data = try? Data(contentsOf: credentialsFile) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: credentialsFile)
        try? FileManager.default.removeItem(at: bridgesFile)
        // Clean up legacy cert_hash file from TOFU era
        try? FileManager.default.removeItem(
            at: storageDirectory.appendingPathComponent("cert_hash")
        )
    }

    // MARK: - Multi-bridge storage

    private static var bridgesFile: URL {
        storageDirectory.appendingPathComponent("bridges.json")
    }

    /// Adds or updates a bridge in the stored array (matched by `id`).
    static func saveBridge(_ bridge: BridgeCredentials) throws {
        try ensureStorageDirectory()
        var bridges = loadBridgesFromDisk()
        if let index = bridges.firstIndex(where: { $0.id == bridge.id }) {
            bridges[index] = bridge
        } else {
            bridges.append(bridge)
        }
        let data = try JSONEncoder().encode(bridges)
        try writeRestricted(data, to: bridgesFile)
        try? saveLastBridgeIP(bridge.bridgeIP)
    }

    /// Removes a bridge by ID from the stored array.
    static func removeBridge(id: String) throws {
        try ensureStorageDirectory()
        var bridges = loadBridgesFromDisk()
        bridges.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(bridges)
        try writeRestricted(data, to: bridgesFile)
    }

    /// Loads all bridges. Migrates from legacy `credentials.json` on first call if needed.
    static func loadBridges() -> [BridgeCredentials] {
        if FileManager.default.fileExists(atPath: bridgesFile.path) {
            return loadBridgesFromDisk()
        }

        // Migrate legacy single-credential file
        if let data = try? Data(contentsOf: credentialsFile),
           let old = try? JSONDecoder().decode(Credentials.self, from: data) {
            let migrated = BridgeCredentials(
                id: "migrated-\(old.bridgeIP)",
                bridgeIP: old.bridgeIP,
                applicationKey: old.applicationKey,
                name: "Hue Bridge"
            )
            if (try? saveBridge(migrated)) != nil {
                try? FileManager.default.removeItem(at: credentialsFile)
            }
            return [migrated]
        }

        return []
    }

    private static func loadBridgesFromDisk() -> [BridgeCredentials] {
        guard let data = try? Data(contentsOf: bridgesFile) else { return [] }
        return (try? JSONDecoder().decode([BridgeCredentials].self, from: data)) ?? []
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
}
