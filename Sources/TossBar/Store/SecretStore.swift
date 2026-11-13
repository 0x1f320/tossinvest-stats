import Foundation

/// Storage for the API keys and the cached access token.
///
/// Values live in user-only files under `~/Library/Application Support/TossBar/`
/// (directory `0700`, files `0600`) instead of the Keychain. The Keychain asks for the
/// login password again every time the code signature changes, which happens on every
/// rebuild of an ad-hoc signed app.
enum SecretStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TossBar", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(
                at: base,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        // The folder may already exist with looser permissions, so tighten it every time.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        return base
    }

    private static func url(_ name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    static func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let target = url(name)
        // Create the file as 0600 before writing, so it is never readable by others.
        if !FileManager.default.fileExists(atPath: target.path) {
            FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? data.write(to: target, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    static func delete(name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }
}

struct Credentials: Codable, Hashable, Sendable {
    var clientId: String
    var clientSecret: String

    private static let fileName = "credentials"

    static func load() -> Credentials? { SecretStore.read(Credentials.self, name: fileName) }
    static func save(_ value: Credentials) { SecretStore.write(value, name: fileName) }
    static func clear() { SecretStore.delete(name: fileName) }
}

struct CachedToken: Codable, Hashable, Sendable {
    var clientId: String
    var accessToken: String
    var expiresAt: Date

    private static let fileName = "access-token"

    static func load() -> CachedToken? { SecretStore.read(CachedToken.self, name: fileName) }
    static func save(_ value: CachedToken) { SecretStore.write(value, name: fileName) }
    static func clear() { SecretStore.delete(name: fileName) }
}
