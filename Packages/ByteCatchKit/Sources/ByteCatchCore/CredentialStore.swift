import CryptoKit
import Foundation

/// One saved server and how the app signs in to it.
public struct Credentials: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var server: ServerURL
    public var token: String?
    public var username: String?
    /// Set when signed in with an API key instead of a password.
    public var apiKey: String?
    /// Optional label chosen by the user, shown instead of the address.
    public var name: String?

    public init(id: UUID = UUID(), server: ServerURL, token: String? = nil, username: String? = nil, apiKey: String? = nil,
                name: String? = nil) {
        self.id = id
        self.name = name
        self.server = server
        self.token = token
        self.username = username
        self.apiKey = apiKey
    }

    public var isSignedIn: Bool { token != nil || apiKey != nil }

    /// A client for this login, or nil when not signed in.
    public func makeClient(transport: any HTTPTransport = URLSession.shared) -> APIClient? {
        guard isSignedIn else { return nil }
        return APIClient(server: server, token: token, apiKey: apiKey, transport: transport)
    }

    /// The same server and account, signed out.
    public var signedOut: Credentials {
        var copy = self
        copy.token = nil
        copy.apiKey = nil
        return copy
    }

    private enum CodingKeys: String, CodingKey { case id, server, token, username, apiKey, name }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            server: try c.decode(ServerURL.self, forKey: .server),
            token: try c.decodeIfPresent(String.self, forKey: .token),
            username: try c.decodeIfPresent(String.self, forKey: .username),
            apiKey: try c.decodeIfPresent(String.self, forKey: .apiKey),
            name: try c.decodeIfPresent(String.self, forKey: .name)
        )
    }
}

/// Every saved server, and which one is in use.
public struct AccountList: Codable, Equatable, Sendable {
    public var accounts: [Credentials] = []
    public var activeID: UUID?

    public init(accounts: [Credentials] = [], activeID: UUID? = nil) {
        self.accounts = accounts
        self.activeID = activeID
    }

    public var active: Credentials? {
        activeID.flatMap { id in accounts.first { $0.id == id } }
    }

    /// Reads the current format, or a single `Credentials` saved by earlier versions.
    public static func decode(_ data: Data) throws -> AccountList {
        if let list = try? JSONDecoder().decode(AccountList.self, from: data) { return list.mergingDuplicates() }
        var single = try JSONDecoder().decode(Credentials.self, from: data)
        // Earlier versions saved no id; derive a stable one so every read names the same account.
        single.id = Self.stableID(for: "legacy:" + single.server.cacheKey)
        return AccountList(accounts: [single], activeID: single.id)
    }

    /// Identical logins saved twice collapse into one (the active copy wins), keeping first-seen order.
    func mergingDuplicates() -> AccountList {
        func sameLogin(_ a: Credentials, _ b: Credentials) -> Bool {
            a.server == b.server && a.token == b.token && a.apiKey == b.apiKey && a.username == b.username
        }
        var merged: [Credentials] = []
        for account in accounts {
            if let index = merged.firstIndex(where: { sameLogin($0, account) }) {
                if account.id == activeID { merged[index] = account }
            } else {
                merged.append(account)
            }
        }
        let active = merged.contains { $0.id == activeID } ? activeID : nil
        return AccountList(accounts: merged, activeID: active)
    }

    static func stableID(for text: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Persists the saved servers. `load`/`save`/`clear` act on the active account, which is all the
/// share extension and intents need.
public protocol CredentialStore: Sendable {
    func loadAll() -> AccountList
    func saveAll(_ list: AccountList) throws
}

extension CredentialStore {
    public func load() -> Credentials? { loadAll().active }

    /// Adds or updates the account (matched by `id`) and makes it active.
    public func save(_ credentials: Credentials) throws {
        var list = loadAll()
        if let index = list.accounts.firstIndex(where: { $0.id == credentials.id }) {
            list.accounts[index] = credentials
        } else {
            list.accounts.append(credentials)
        }
        list.activeID = credentials.id
        try saveAll(list)
    }

    /// Removes the active account; no account is active afterwards.
    public func clear() throws {
        var list = loadAll()
        list.accounts.removeAll { $0.id == list.activeID }
        list.activeID = nil
        try saveAll(list)
    }
}

/// For tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var list: AccountList

    public init(_ credentials: Credentials? = nil) {
        list = credentials.map { AccountList(accounts: [$0], activeID: $0.id) } ?? AccountList()
    }

    public func loadAll() -> AccountList { lock.withLock { list } }
    public func saveAll(_ list: AccountList) throws { lock.withLock { self.list = list } }
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

    public func loadAll() -> AccountList {
        let main = primary.loadAll()
        return main.accounts.isEmpty ? fallback.loadAll() : main
    }

    public func saveAll(_ list: AccountList) throws {
        do {
            try primary.saveAll(list)
        } catch {
            try fallback.saveAll(list)
        }
    }
}
