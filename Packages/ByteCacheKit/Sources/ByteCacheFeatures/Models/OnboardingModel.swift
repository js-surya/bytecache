import ByteCacheCore
import Foundation
import Observation

/// Drives the server-setup and login screens.
@MainActor @Observable
public final class OnboardingModel {
    public static let demoServer = "https://bytestash-demo.pikapod.net"

    public enum LoginMethod: String, CaseIterable, Identifiable, Sendable {
        case password, apiKey
        public var id: String { rawValue }
        public var title: String { self == .password ? "Password" : "API Key" }
    }

    public static let rejectedKeyMessage = "That API key wasn't accepted. Create one in ByteStash under Settings → API Keys."

    public var serverText = ""
    public var method = LoginMethod.password
    public var username = ""
    public var password = ""
    public var apiKey = ""
    /// Create Account instead of Sign In (CP-75); only offered when the server allows it.
    public var creatingAccount = false
    public var confirmPassword = ""
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?

    public let session: SessionManager

    public init(session: SessionManager) {
        self.session = session
    }

    public var canConnect: Bool {
        !isWorking && !serverText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var canLogin: Bool {
        guard !isWorking else { return false }
        switch method {
        case .password:
            let filled = !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
            return creatingAccount ? filled && password == confirmPassword : filled
        case .apiKey: return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Shown under the fields while the two passwords differ.
    public var passwordsDiffer: Bool {
        creatingAccount && !confirmPassword.isEmpty && password != confirmPassword
    }

    public var canCreateAccount: Bool { session.canCreateAccount }

    public func toggleCreatingAccount() {
        creatingAccount.toggle()
        method = .password
        confirmPassword = ""
        errorMessage = nil
    }

    /// Fills the public demo server and its published login.
    public func useDemoServer() {
        serverText = Self.demoServer
        username = "demo"
        password = "demodemo"
    }

    public func connect() async {
        await run { [self] () async throws(APIError) in try await session.connect(serverText) }
        guard errorMessage == nil else { return }
        // Don't carry one server's secrets to the next (the demo button fills its public login on purpose).
        apiKey = ""
        if serverText != Self.demoServer { password = "" }
    }

    public func login() async {
        switch method {
        case .password:
            let name = username.trimmingCharacters(in: .whitespaces)
            if creatingAccount {
                await run { [self] () async throws(APIError) in try await session.register(username: name, password: password) }
            } else {
                await run { [self] () async throws(APIError) in try await session.login(username: name, password: password) }
            }
            if errorMessage == nil {
                password = ""
                confirmPassword = ""
                creatingAccount = false
            }
        case .apiKey:
            await run { [self] () async throws(APIError) in try await session.loginWithAPIKey(apiKey) }
            if errorMessage == ErrorText.message(for: .unauthorized) { errorMessage = Self.rejectedKeyMessage }
            if errorMessage == nil { apiKey = "" }
        }
    }

    /// Servers saved here or synced from iCloud, offered on the server screen so a new device
    /// doesn't need the address typed again. Logins don't sync, so each one asks to sign in.
    public var savedServers: [Credentials] { session.accounts }

    public func useSavedServer(_ id: UUID) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        await session.switchTo(id)
    }

    public func cancelAddServer() async {
        errorMessage = nil
        await session.cancelAddServer()
    }

    public func changeServer() {
        errorMessage = nil
        session.changeServer()
    }

    private func run(_ work: () async throws(APIError) -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }
}
