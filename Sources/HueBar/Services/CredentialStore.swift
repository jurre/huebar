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

    struct Credentials: Codable {
        var bridgeIP: String
        var applicationKey: String
        var certificateHash: String?
    }

    static func save(credentials: Credentials) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDirectory.path) {
            try fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storageDirectory.path)
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: credentialsFile, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsFile.path)
    }

    static func load() -> Credentials? {
        guard let data = try? Data(contentsOf: credentialsFile) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func updateCertificateHash(_ hash: String) throws {
        // Save cert hash independently so TOFU works before credentials exist
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDirectory.path) {
            try fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storageDirectory.path)
        let data = Data(hash.utf8)
        try data.write(to: certHashFile, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: certHashFile.path)

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

    static func deleteCertificateHash() {
        try? FileManager.default.removeItem(at: certHashFile)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: credentialsFile)
        deleteCertificateHash()
    }
}
