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

    public static let ssoOnlyMessage = "This server only allows single sign-on, but it isn't set up there."
    /// Shown as the user name for API-key logins; ByteStash has no "who am I" for keys.
    public nonisolated static let apiKeyUserName = "API key"

    public private(set) var state: State = .needsServer {
        didSet { if case .signedIn = state { sessionExpired = false } }
    }
    /// The server stopped accepting the saved login while the app was open; sign-in says so.
    public private(set) var sessionExpired = false
    /// Goes up each time the app moves from an expired login to its backup key, so lists that just
    /// failed can load again.
    public private(set) var backupKeySwitches = 0
    /// Signed in on the backup key after the login expired (CP-91): snippets work, share links and
    /// account management need a new sign-in. Stored (not computed from `credentials`, which isn't
    /// observed) so screens update when it changes.
    public private(set) var isUsingBackupKey = false
    /// The user chose "Stay signed in" for the current login (also known on the sign-in screen).
    public private(set) var staysSignedIn = false
    /// "Stay signed in" applies: a password or single sign-on login, or one already on its backup key.
    /// (A key the user typed in never expires, so it needs no backup.)
    public var canStaySignedIn: Bool {
        guard case .signedIn = state, let current = credentials else { return false }
        return current.token != nil || current.isUsingBackupKey
    }
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
    @ObservationIgnored private var credentials: Credentials? {
        didSet {
            isUsingBackupKey = credentials?.isUsingBackupKey ?? false
            staysSignedIn = credentials?.staySignedIn ?? false
        }
    }
    /// A backup key is being made: a second request (sign-in and the app's own check at once) would
    /// make a second key.
    @ObservationIgnored private var makingBackupKey = false
    @ObservationIgnored private var lastConfig = AuthConfig()
    /// The server's single sign-on, when it offers one (CP-72); read with its auth config.
    public private(set) var sso: SSOConfig?
    @ObservationIgnored private var accountToReturnTo: UUID?
    /// The server typed in on this visit to the server screen, until it's signed in.
    @ObservationIgnored private var typedInID: UUID?
    /// When the backup key took over. Rejections that arrive shortly after come from requests sent
    /// with the expired login, not from the key.
    @ObservationIgnored private var backupKeySince: ContinuousClock.Instant?
    /// How long after switching to the backup key a rejection is put down to an older request.
    @ObservationIgnored var backupKeyGracePeriod: Duration = .seconds(15)

    /// An MCP client for the current server, using `apiKey` (the key assistants will use).
    public func mcpClient(apiKey: String) -> MCPClient? {
        guard let server = credentials?.server else { return nil }
        return MCPClient(server: server, apiKey: apiKey, transport: transport)
    }

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
        } else {
            // A server without password logins is only usable through its single sign-on.
            sso = config.disableInternalAccounts ? await Self.ssoConfig(api) : nil
            if config.disableInternalAccounts && sso == nil { throw .forbidden(Self.ssoOnlyMessage) }
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

    /// Whether the sign-in screen offers Create Account: the server allows new accounts, or has none yet.
    public var canCreateAccount: Bool {
        guard case .needsLogin(_, let config) = state else { return false }
        return !config.disableAccounts && (config.allowNewAccounts || !config.hasUsers)
    }

    /// Creates an account and signs in with it.
    public func register(username: String, password: String) async throws(APIError) {
        guard case .needsLogin(let server, _) = state else { throw .invalidServer }
        let result = try await APIClient(server: server, token: nil, transport: transport)
            .register(username: username, password: password)
        AppLog.shared.record("session", "created an account")
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
        typedInID = nil
        AppLog.shared.record("session", "signed in with an API key")
        state = .signedIn(server: server, user: Self.apiKeyUser)
    }

    /// Forgets the login but keeps the server, so the login screen is one step away. The backup key
    /// is revoked when the login still allows it (keys can only be managed with a password login).
    public func signOut() {
        if let current = credentials, let id = current.backupKeyID, current.token != nil,
           let client = current.makeClient(transport: transport) {
            Task { try? await client.deleteAPIKey(id: id) }
        }
        dropToLogin()
    }

    /// Turns "Stay signed in" on (makes the backup key) or off (revokes and forgets it). Off while
    /// the app is already running on the key signs out, since the login itself has expired.
    /// Returns false when the key couldn't be made.
    @discardableResult
    public func setStaySignedIn(_ on: Bool, keyName: String) async -> Bool {
        guard var current = credentials else { return false }
        current.staySignedIn = on
        persist(current)
        if on { return await ensureBackupKey(name: keyName) }
        if current.isUsingBackupKey {
            AppLog.shared.record("session", "stay signed in turned off while using the backup key; signing out")
            dropToLogin()
            return true
        }
        if let id = current.backupKeyID, current.token != nil, let client = current.makeClient(transport: transport) {
            try? await client.deleteAPIKey(id: id)
        }
        guard var latest = credentials, latest.id == current.id else { return true }
        latest.backupKey = nil
        latest.backupKeyID = nil
        persist(latest)
        AppLog.shared.record("session", "stay signed in turned off; backup key removed")
        return true
    }

    /// When the user chose "Stay signed in", makes the backup key that keeps the app signed in once
    /// the server ends a password or single sign-on login (ByteStash logins expire, 24 hours by
    /// default). Does nothing otherwise, or when there's a key already. `name` says which device
    /// it's for. Returns false when the key couldn't be made.
    @discardableResult
    public func ensureBackupKey(name: String) async -> Bool {
        guard case .signedIn = state, let current = credentials, current.staySignedIn else { return false }
        guard current.backupKey == nil else { return true }
        guard current.token != nil, current.apiKey == nil, !makingBackupKey,
              let client = current.makeClient(transport: transport) else { return false }
        makingBackupKey = true
        defer { makingBackupKey = false }
        guard let created = try? await client.createAPIKey(name: name) else {
            AppLog.shared.record("session", "couldn't make a backup key; the login will need renewing when it expires")
            return false
        }
        // The account may have changed while the key was being made.
        guard var latest = credentials, latest.id == current.id else { return false }
        latest.backupKey = created.key
        latest.backupKeyID = created.info.id
        persist(latest)
        AppLog.shared.record("session", "made a backup key to stay signed in")
        return true
    }

    /// Forgets the current server and shows setup; Cancel there returns to another saved server, if any.
    public func changeServer() {
        guard let id = credentials?.id else { return }
        if id == typedInID {
            // Usually a typo: forget it.
            removeActiveSynchronously(id)
        } else {
            // A saved server (maybe from iCloud): keep it listed, here and on other devices.
            leaveActiveSynchronously()
        }
        typedInID = nil
        accountToReturnTo = accounts.first?.id
    }

    /// Call when any request returns 401; signs out cleanly and shows login.
    #if DEBUG
    /// Debug: swaps the login for a session token the server no longer accepts, to show what an
    /// expired session looks like (`-BCExpireSession`).
    public func debugExpireSession() {
        guard case .signedIn = state, var current = credentials else { return }
        current.apiKey = nil
        current.token = "expired.session.token"
        credentials = current
    }
    #endif

    public func handleUnauthorized() {
        guard case .signedIn = state else { return }
        if switchToBackupKey() { return }
        if isUsingBackupKey, let since = backupKeySince, ContinuousClock.now - since < backupKeyGracePeriod {
            AppLog.shared.record("session", "ignored a rejection of a request sent before the switch to the backup key")
            return
        }
        AppLog.shared.record("session", "server rejected the login (401 or invalid token); showing sign-in")
        sessionExpired = true
        dropToLogin()
    }

    /// The login was rejected: carries on with the backup key, if there is one not yet in use.
    private func switchToBackupKey() -> Bool {
        guard var current = credentials, let key = current.backupKey, !current.isUsingBackupKey else { return false }
        current.token = nil
        current.apiKey = key
        persist(current)
        backupKeySince = .now
        backupKeySwitches += 1
        AppLog.shared.record("session", "login expired; using the backup key")
        return true
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

    /// Renames a saved server and/or moves it to a new address. `name` nil keeps the name; blank
    /// removes it. A new address is checked first and keeps the login (same server, new address);
    /// if the server rejects it there, the usual sign-in screen appears.
    public func updateServer(_ id: UUID, name: String?, address: String) async throws(APIError) {
        var list = store.loadAll()
        guard let index = list.accounts.firstIndex(where: { $0.id == id }) else { return }
        let server = try ServerURL(address)
        guard !list.accounts.contains(where: { $0.id != id && $0.server == server }) else { throw .duplicateServer }
        var updated = list.accounts[index]
        let moved = server != updated.server
        if moved {
            lastConfig = try await APIClient(server: server, token: nil, transport: transport).authConfig()
            updated.server = server
        }
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.name = trimmed.isEmpty ? nil : trimmed
        }
        list.accounts[index] = updated
        try? store.saveAll(list)
        accounts = list.accounts
        guard credentials?.id == id else { return }
        if moved {
            await activate(updated)
        } else {
            credentials = updated
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

    /// The user to show for a login: its username, or "API key" for a key the user entered.
    private static func displayUser(_ credentials: Credentials) -> User {
        if credentials.apiKey != nil, !credentials.isUsingBackupKey { return apiKeyUser }
        return User(id: 0, username: credentials.username ?? "")
    }

    private func leaveActiveSynchronously() {
        var list = store.loadAll()
        list.activeID = nil
        try? store.saveAll(list)
        credentials = nil
        state = .needsServer
    }

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
                state = .signedIn(server: stored.server, user: Self.displayUser(stored))
            } else {
                let user = try await client.verify()
                var updated = stored
                updated.username = user.username
                persist(updated)
                state = .signedIn(server: stored.server, user: user)
            }
        } catch .unauthorized {
            // An expired login with a backup key carries on with the key.
            if stored.backupKey != nil, !stored.isUsingBackupKey {
                credentials = stored
                state = .signedIn(server: stored.server, user: User(id: 0, username: stored.username ?? ""))
                if switchToBackupKey() { return }
            }
            persist(stored.signedOut)
            sessionExpired = stored.token != nil
            await showLogin(server: stored.server)
        } catch {
            // Offline, server trouble, or a 403 that isn't about the login (a proxy or VPN while the
            // network recovers): stay signed in so cached snippets remain browsable.
            state = .signedIn(server: stored.server, user: Self.displayUser(stored))
        }
    }

    /// Reuses a saved, signed-out account for the same server; otherwise starts a new one.
    private func beginAccount(on server: ServerURL) {
        let existing = store.loadAll().accounts.first { $0.server == server && !$0.isSignedIn }
        credentials = existing ?? Credentials(server: server)
        typedInID = existing == nil ? credentials?.id : nil
    }

    /// Signs in with the login single sign-on handed back (the server's `bytestash_token`).
    public func signIn(ssoToken: String) async throws(APIError) {
        guard case .needsLogin(let server, _) = state else { throw .invalidServer }
        let user = try await APIClient(server: server, token: ssoToken, transport: transport).verify()
        signIn(token: ssoToken, user: user, how: "single sign-on")
    }

    /// Reads whether the server on the sign-in screen offers single sign-on (the sign-in screen calls it).
    public func loadSSO() async {
        guard case .needsLogin(let server, _) = state else { return }
        let found = await Self.ssoConfig(APIClient(server: server, token: nil, transport: transport))
        if case .needsLogin(let now, _) = state, now == server { sso = found }
    }

    private static func ssoConfig(_ api: APIClient) async -> SSOConfig? {
        guard let config = try? await api.ssoConfig(), config.enabled else { return nil }
        return config
    }

    private func signIn(token: String, user: User, how: String = "a password") {
        guard var current = credentials else { return }
        typedInID = nil
        AppLog.shared.record("session", "signed in with \(how)")
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
        let api = APIClient(server: server, token: nil, transport: transport)
        if let config = try? await api.authConfig() {
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
