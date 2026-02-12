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
        guard var creds = load() else { return }
        creds.certificateHash = hash
        try save(credentials: creds)
    }

    static func pinnedCertificateHash() -> String? {
        load()?.certificateHash
    }

    static func delete() {
        try? FileManager.default.removeItem(at: credentialsFile)
    }
}
