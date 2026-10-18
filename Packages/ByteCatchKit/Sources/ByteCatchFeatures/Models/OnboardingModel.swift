import ByteCatchCore
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
        case .password: return !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        case .apiKey: return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
            await run { [self] () async throws(APIError) in try await session.login(username: name, password: password) }
            if errorMessage == nil { password = "" }
        case .apiKey:
            await run { [self] () async throws(APIError) in try await session.loginWithAPIKey(apiKey) }
            if errorMessage == ErrorText.message(for: .unauthorized) { errorMessage = Self.rejectedKeyMessage }
            if errorMessage == nil { apiKey = "" }
        }
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
