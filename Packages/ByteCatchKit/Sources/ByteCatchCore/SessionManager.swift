import Foundation
import Observation

/// Owns sign-in state for the active server and the list of saved servers. It does not intercept
/// API calls: any caller that gets `.unauthorized` must call `handleUnauthorized()`.
@MainActor @Observable
public final class SessionManager {
    public enum State: Equatable {
        case needsServer
        case needsLogin(server: ServerURL, config: AuthConfig)
        case signedIn(server: ServerURL, user: User)
    }

    public static let ssoOnlyMessage = "This server only allows single sign-on, which ByteCatch doesn't support yet."
    /// Shown as the user name for API-key logins; ByteStash has no "who am I" for keys.
    public nonisolated static let apiKeyUserName = "API key"

    public private(set) var state: State = .needsServer
    /// Every saved server, in the order they were added.
    public private(set) var accounts: [Credentials] = []
    public var activeAccountID: UUID? { credentials?.id }
    /// Servers removed on this device since launch, for iCloud sync to spread.
    public private(set) var removedAccountIDs: Set<UUID> = []

    /// True while adding a server when there is another one to go back to.
    public var canCancelAddServer: Bool {
        state == .needsServer && accountToReturnTo != nil
    }

    /// A client for the current server and login; nil unless signed in.
    public var client: APIClient? {
        guard case .signedIn = state else { return nil }
        return credentials?.makeClient(transport: transport)
    }

    @ObservationIgnored private let store: any CredentialStore
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private var credentials: Credentials?
    @ObservationIgnored private var lastConfig = AuthConfig()
    @ObservationIgnored private var accountToReturnTo: UUID?

    public init(store: any CredentialStore, transport: any HTTPTransport = URLSession.shared) {
        self.store = store
        self.transport = transport
    }

    /// Call on launch: validates the active account's login and picks the right screen.
    public func restore() async {
        accounts = store.loadAll().accounts
        guard let stored = store.load() else {
            credentials = nil
            state = .needsServer
            return
        }
        await activate(stored)
    }

    /// Validates the server address and decides whether a login is needed. Adds a new saved server.
    public func connect(_ rawURL: String) async throws(APIError) {
        let server = try ServerURL(rawURL)
        let api = APIClient(server: server, token: nil, transport: transport)
        let config = try await api.authConfig()
        lastConfig = config

        if !config.authRequired {
            let result = try await api.anonymousLogin()
            beginAccount(on: server)
            signIn(token: result.token, user: result.user)
        } else if config.disableInternalAccounts {
            throw .forbidden(Self.ssoOnlyMessage)
        } else {
            beginAccount(on: server)
            persist(credentials!)
            state = .needsLogin(server: server, config: config)
        }
        accountToReturnTo = nil
    }

    public func login(username: String, password: String) async throws(APIError) {
        guard case .needsLogin(let server, _) = state else { throw .invalidServer }
        let result = try await APIClient(server: server, token: nil, transport: transport)
            .login(username: username, password: password)
        signIn(token: result.token, user: result.user)
    }

    /// Signs in with an API key (ByteStash → Settings → API Keys). Checked by loading snippet metadata.
    public func loginWithAPIKey(_ rawKey: String) async throws(APIError) {
        guard case .needsLogin(let server, _) = state, var current = credentials else { throw .invalidServer }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await APIClient(server: server, token: nil, apiKey: key, transport: transport).metadata()
        current.token = nil
        current.username = nil
        current.apiKey = key
        persist(current)
        state = .signedIn(server: server, user: Self.apiKeyUser)
    }

    /// Forgets the login but keeps the server, so the login screen is one step away.
    public func signOut() {
        dropToLogin()
    }

    /// Forgets the current server and shows setup; Cancel there returns to another saved server, if any.
    public func changeServer() {
        guard let id = credentials?.id else { return }
        removeActiveSynchronously(id)
        accountToReturnTo = accounts.first?.id
    }

    /// Call when any request returns 401; signs out cleanly and shows login.
    public func handleUnauthorized() {
        guard case .signedIn = state else { return }
        dropToLogin()
    }

    // MARK: Several servers

    /// Shows server setup for an extra server; `cancelAddServer()` goes back.
    public func addServer() {
        accountToReturnTo = credentials?.id
        state = .needsServer
    }

    public func cancelAddServer() async {
        guard let id = accountToReturnTo else { return }
        accountToReturnTo = nil
        await switchTo(id)
    }

    public func switchTo(_ id: UUID) async {
        guard let account = store.loadAll().accounts.first(where: { $0.id == id }) else { return }
        accountToReturnTo = nil
        persist(account)
        await activate(account)
    }

    public func removeAccount(_ id: UUID) async {
        removedAccountIDs.insert(id)
        var list = store.loadAll()
        let wasActive = list.activeID == id || credentials?.id == id
        list.accounts.removeAll { $0.id == id }
        if wasActive { list.activeID = nil }
        try? store.saveAll(list)
        accounts = list.accounts
        if accountToReturnTo == id { accountToReturnTo = nil }
        guard wasActive else { return }
        credentials = nil
        if let next = list.accounts.first {
            await switchTo(next.id)
        } else {
            state = .needsServer
        }
    }

    /// Applies the server list from iCloud. Keeps the current session unless its server was removed.
    public func applySyncedServers(_ payload: ServerListPayload) async {
        let current = store.loadAll()
        let merged = current.merging(payload)
        guard merged != current else { return }
        try? store.saveAll(merged)
        accounts = merged.accounts
        guard let active = credentials, !merged.accounts.contains(where: { $0.id == active.id }) else { return }
        credentials = nil
        if let next = merged.accounts.first {
            await switchTo(next.id)
        } else {
            state = .needsServer
        }
    }

    // MARK: Private

    private static let apiKeyUser = User(id: 0, username: apiKeyUserName)

    private func removeActiveSynchronously(_ id: UUID) {
        guard credentials?.id == id else { return }
        removedAccountIDs.insert(id)
        var list = store.loadAll()
        list.accounts.removeAll { $0.id == id }
        list.activeID = nil
        try? store.saveAll(list)
        accounts = list.accounts
        credentials = nil
        state = .needsServer
    }

    /// Validates a stored login and sets the screen.
    private func activate(_ stored: Credentials) async {
        credentials = stored
        guard let client = stored.makeClient(transport: transport) else {
            await showLogin(server: stored.server)
            return
        }
        do {
            if stored.apiKey != nil {
                _ = try await client.metadata()
                state = .signedIn(server: stored.server, user: Self.apiKeyUser)
            } else {
                let user = try await client.verify()
                var updated = stored
                updated.username = user.username
                persist(updated)
                state = .signedIn(server: stored.server, user: user)
            }
        } catch .unauthorized, .forbidden {
            persist(stored.signedOut)
            await showLogin(server: stored.server)
        } catch {
            // Offline or server trouble: stay signed in so cached snippets remain browsable.
            let name = stored.apiKey != nil ? Self.apiKeyUserName : stored.username ?? ""
            state = .signedIn(server: stored.server, user: User(id: 0, username: name))
        }
    }

    /// Reuses a saved, signed-out account for the same server; otherwise starts a new one.
    private func beginAccount(on server: ServerURL) {
        let existing = store.loadAll().accounts.first { $0.server == server && !$0.isSignedIn }
        credentials = existing ?? Credentials(server: server)
    }

    private func signIn(token: String, user: User) {
        guard var current = credentials else { return }
        current.token = token
        current.apiKey = nil
        current.username = user.username
        persist(current)
        state = .signedIn(server: current.server, user: user)
    }

    private func dropToLogin() {
        guard let current = credentials else { return }
        persist(current.signedOut)
        state = .needsLogin(server: current.server, config: lastConfig)
    }

    private func showLogin(server: ServerURL) async {
        if let config = try? await APIClient(server: server, token: nil, transport: transport).authConfig() {
            lastConfig = config
        }
        state = .needsLogin(server: server, config: lastConfig)
    }

    /// Keychain failures must not block sign-in; the session just won't survive a relaunch.
    private func persist(_ new: Credentials) {
        credentials = new
        try? store.save(new)
        accounts = store.loadAll().accounts
    }
}
