import Foundation

/// Stores Hue Bridge credentials in ~/Library/Application Support/HueBar/
enum CredentialStore {
    private static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("HueBar", isDirectory: true)
    }()

    private static var credentialsFile: URL {
        appSupportDir.appendingPathComponent("credentials.json")
    }

    struct Credentials: Codable {
        let bridgeIP: String
        let applicationKey: String
    }

    static func save(credentials: Credentials) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: appSupportDir.path) {
            try fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: credentialsFile, options: .atomic)
        // Restrict file permissions to owner only
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsFile.path)
    }

    static func load() -> Credentials? {
        guard let data = try? Data(contentsOf: credentialsFile) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: credentialsFile)
    }
}
