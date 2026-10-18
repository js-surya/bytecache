import ByteCatchCore
import Foundation
import Observation

/// Drives the server-setup and login screens.
@MainActor @Observable
public final class OnboardingModel {
    public static let demoServer = "https://bytestash-demo.pikapod.net"

    public var serverText = ""
    public var username = ""
    public var password = ""
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
        !isWorking && !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    /// Fills the public demo server and its published login.
    public func useDemoServer() {
        serverText = Self.demoServer
        username = "demo"
        password = "demodemo"
    }

    public func connect() async {
        await run { [self] () async throws(APIError) in try await session.connect(serverText) }
    }

    public func login() async {
        let name = username.trimmingCharacters(in: .whitespaces)
        await run { [self] () async throws(APIError) in try await session.login(username: name, password: password) }
        if errorMessage == nil { password = "" }
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
