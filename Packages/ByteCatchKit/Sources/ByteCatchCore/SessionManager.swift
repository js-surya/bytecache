import Foundation
import Observation

/// Owns sign-in state. It does not intercept API calls: any caller that gets `.unauthorized`
/// must call `handleUnauthorized()`.
@MainActor @Observable
public final class SessionManager {
    public enum State: Equatable {
        case needsServer
        case needsLogin(server: ServerURL, config: AuthConfig)
        case signedIn(server: ServerURL, user: User)
    }

    public static let ssoOnlyMessage = "This server only allows single sign-on, which ByteCatch doesn't support yet."

    public private(set) var state: State = .needsServer

    /// A client for the current server and token; nil unless signed in.
    public var client: APIClient? {
        guard case .signedIn(let server, _) = state, let token = credentials?.token else { return nil }
        return APIClient(server: server, token: token, transport: transport)
    }

    @ObservationIgnored private let store: any CredentialStore
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private var credentials: Credentials?
    @ObservationIgnored private var lastConfig = AuthConfig()

    public init(store: any CredentialStore, transport: any HTTPTransport = URLSession.shared) {
        self.store = store
        self.transport = transport
    }

    /// Call on launch: validates the stored token and picks the right screen.
    public func restore() async {
        guard let stored = store.load() else {
            state = .needsServer
            return
        }
        credentials = stored
        guard let token = stored.token else {
            await showLogin(server: stored.server)
            return
        }
        do {
            let user = try await APIClient(server: stored.server, token: token, transport: transport).verify()
            persist(Credentials(server: stored.server, token: token, username: user.username))
            state = .signedIn(server: stored.server, user: user)
        } catch .unauthorized, .forbidden {
            persist(Credentials(server: stored.server, token: nil, username: stored.username))
            await showLogin(server: stored.server)
        } catch {
            // Offline or server trouble: stay signed in so cached snippets remain browsable.
            state = .signedIn(server: stored.server, user: User(id: 0, username: stored.username ?? ""))
        }
    }

    /// Validates the server address and decides whether a login is needed.
    public func connect(_ rawURL: String) async throws(APIError) {
        let server = try ServerURL(rawURL)
        let api = APIClient(server: server, token: nil, transport: transport)
        let config = try await api.authConfig()
        lastConfig = config

        if !config.authRequired {
            let result = try await api.anonymousLogin()
            signIn(server: server, token: result.token, user: result.user)
        } else if config.disableInternalAccounts {
            throw .forbidden(Self.ssoOnlyMessage)
        } else {
            persist(Credentials(server: server))
            state = .needsLogin(server: server, config: config)
        }
    }

    public func login(username: String, password: String) async throws(APIError) {
        guard case .needsLogin(let server, _) = state else { throw .invalidServer }
        let result = try await APIClient(server: server, token: nil, transport: transport)
            .login(username: username, password: password)
        signIn(server: server, token: result.token, user: result.user)
    }

    /// Forgets the token but keeps the server, so the login screen is one step away.
    public func signOut() {
        dropToLogin()
    }

    /// Forgets the server and credentials entirely, back to the setup screen.
    public func changeServer() {
        credentials = nil
        try? store.clear()
        state = .needsServer
    }

    /// Call when any request returns 401; signs out cleanly and shows login.
    public func handleUnauthorized() {
        guard case .signedIn = state else { return }
        dropToLogin()
    }

    // MARK: Private

    private func signIn(server: ServerURL, token: String, user: User) {
        persist(Credentials(server: server, token: token, username: user.username))
        state = .signedIn(server: server, user: user)
    }

    private func dropToLogin() {
        let server: ServerURL
        switch state {
        case .needsServer: return
        case .needsLogin(let current, _), .signedIn(let current, _): server = current
        }
        persist(Credentials(server: server, token: nil, username: credentials?.username))
        state = .needsLogin(server: server, config: lastConfig)
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
    }
}
