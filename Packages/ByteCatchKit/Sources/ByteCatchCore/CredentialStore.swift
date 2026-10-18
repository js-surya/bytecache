import Foundation

/// What the app and its share extensions need to talk to the server.
public struct Credentials: Codable, Equatable, Sendable {
    public var server: ServerURL
    public var token: String?
    public var username: String?

    public init(server: ServerURL, token: String? = nil, username: String? = nil) {
        self.server = server
        self.token = token
        self.username = username
    }
}

public protocol CredentialStore: Sendable {
    func load() -> Credentials?
    func save(_ credentials: Credentials) throws
    func clear() throws
}

/// For tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: Credentials?

    public init(_ credentials: Credentials? = nil) {
        self.credentials = credentials
    }

    public func load() -> Credentials? { lock.withLock { credentials } }
    public func save(_ credentials: Credentials) throws { lock.withLock { self.credentials = credentials } }
    public func clear() throws { lock.withLock { credentials = nil } }
}

/// Uses `primary` (the shared keychain group) and falls back when it can't be written — unsigned
/// simulator and local Mac builds lack the keychain-sharing entitlement.
public struct FallbackCredentialStore: CredentialStore {
    private let primary: any CredentialStore
    private let fallback: any CredentialStore

    public init(primary: any CredentialStore, fallback: any CredentialStore) {
        self.primary = primary
        self.fallback = fallback
    }

    public func load() -> Credentials? {
        primary.load() ?? fallback.load()
    }

    public func save(_ credentials: Credentials) throws {
        do {
            try primary.save(credentials)
        } catch {
            try fallback.save(credentials)
        }
    }

    public func clear() throws {
        try? primary.clear()
        try fallback.clear()
    }
}
