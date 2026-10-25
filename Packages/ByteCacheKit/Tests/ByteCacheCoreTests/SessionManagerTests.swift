import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

@MainActor
final class SessionManagerTests: XCTestCase {
    private let server = try! ServerURL("https://x.io")

    private let authConfig = #"{"authRequired":true,"allowNewAccounts":false,"hasUsers":true,"disableAccounts":false,"disableInternalAccounts":false}"#
    private let loginReply = #"{"token":"t","user":{"id":2,"username":"demo","is_admin":false}}"#

    private func ok(_ body: String) -> StubTransport.Reply {
        .response(status: 200, body: body, contentType: "application/json")
    }

    private func status(_ code: Int, _ body: String = "{}") -> StubTransport.Reply {
        .response(status: code, body: body, contentType: "application/json")
    }

    func testConnectThenLoginPersists() async throws {
        let store = InMemoryCredentialStore()
        let session = SessionManager(store: store, transport: StubTransport([ok(authConfig), ok(loginReply)]))

        try await session.connect("x.io/")
        guard case .needsLogin(let connected, _) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(connected, server)
        XCTAssertNil(session.client)

        try await session.login(username: "demo", password: "demodemo")
        XCTAssertEqual(session.state, .signedIn(server: server, user: User(id: 2, username: "demo")))
        XCTAssertEqual(store.load()?.server, server); XCTAssertEqual(store.load()?.token, "t"); XCTAssertEqual(store.load()?.username, "demo")
        XCTAssertEqual(session.client?.token, "t")
    }

    func testConnectToNoAuthServerUsesAnonymousLogin() async throws {
        let stub = StubTransport([ok(#"{"authRequired":false,"hasUsers":false}"#), ok(#"{"token":"anon"}"#)])
        let store = InMemoryCredentialStore()
        let session = SessionManager(store: store, transport: stub)

        try await session.connect("https://x.io")
        guard case .signedIn = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(stub.last.url?.path, "/api/auth/anonymous")
        XCTAssertEqual(store.load()?.token, "anon")
    }

    /// An SSO-only server whose single sign-on isn't enabled can't be used (CP-72 handles enabled ones).
    func testConnectSSOOnlyServerWithoutSSOThrowsForbidden() async {
        let config = #"{"authRequired":true,"disableInternalAccounts":true}"#
        let store = InMemoryCredentialStore()
        let session = SessionManager(store: store, transport: StubTransport([ok(config), ok(#"{"enabled":false}"#)]))
        do {
            try await session.connect("https://x.io")
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .forbidden(SessionManager.ssoOnlyMessage))
        }
        XCTAssertEqual(session.state, .needsServer)
        XCTAssertNil(store.load())
    }

    func testConnectRejectsNonByteStashAddress() async {
        let html = StubTransport.Reply.response(status: 200, body: "<html>", contentType: "text/html")
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport([html]))
        do {
            try await session.connect("https://x.io")
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .notByteStash)
        }
        XCTAssertEqual(session.state, .needsServer)
    }

    func testLoginWithBadPasswordStaysOnLogin() async throws {
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport([ok(authConfig), status(401)]))
        try await session.connect("https://x.io")
        do {
            try await session.login(username: "demo", password: "nope")
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .unauthorized)
        }
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
    }

    func testRestoreWithoutCredentialsNeedsServer() async {
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport())
        await session.restore()
        XCTAssertEqual(session.state, .needsServer)
    }

    func testRestoreWithValidTokenSignsIn() async {
        let store = InMemoryCredentialStore(Credentials(server: server, token: "t", username: "demo"))
        let verify = ok(#"{"valid":true,"user":{"id":2,"username":"demo"}}"#)
        let session = SessionManager(store: store, transport: StubTransport([verify]))
        await session.restore()
        XCTAssertEqual(session.state, .signedIn(server: server, user: User(id: 2, username: "demo")))
    }

    func testRestoreWithExpiredTokenGoesToLogin() async {
        let store = InMemoryCredentialStore(Credentials(server: server, token: "old", username: "demo"))
        let session = SessionManager(store: store, transport: StubTransport([status(401, #"{"valid":false}"#), ok(authConfig)]))
        await session.restore()
        guard case .needsLogin(let kept, _) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(kept, server)
        XCTAssertNil(store.load()?.token)
        XCTAssertEqual(store.load()?.server, server)
    }

    func testRestoreOfflineKeepsSignedIn() async {
        let store = InMemoryCredentialStore(Credentials(server: server, token: "t", username: "demo"))
        let session = SessionManager(store: store, transport: StubTransport([.failure(URLError(.notConnectedToInternet))]))
        await session.restore()
        guard case .signedIn(_, let user) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(user.username, "demo")
        XCTAssertEqual(store.load()?.token, "t")
        XCTAssertNotNil(session.client)
    }

    func testHandleUnauthorizedClearsToken() async throws {
        let store = InMemoryCredentialStore()
        let session = SessionManager(store: store, transport: StubTransport([ok(authConfig), ok(loginReply)]))
        try await session.connect("https://x.io")
        try await session.login(username: "demo", password: "demodemo")

        session.handleUnauthorized()
        guard case .needsLogin(let kept, _) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(kept, server)
        XCTAssertNil(store.load()?.token)
        XCTAssertNil(session.client)

        session.handleUnauthorized() // already signed out: no-op
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
    }

    func testSignOutReturnsToLoginKeepingServer() async throws {
        let store = InMemoryCredentialStore()
        let session = SessionManager(store: store, transport: StubTransport([ok(authConfig), ok(loginReply)]))
        try await session.connect("https://x.io")
        try await session.login(username: "demo", password: "demodemo")

        session.signOut()
        guard case .needsLogin(let kept, _) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(kept, server)
        XCTAssertEqual(store.load()?.server, server); XCTAssertEqual(store.load()?.token, nil); XCTAssertEqual(store.load()?.username, "demo")
    }

    // MARK: Staying signed in (CP-91)

    private let invalidToken = #"{"error":"Invalid token"}"#
    private let createdKey = #"{"id":7,"name":"ByteCache on iPhone","key":"backup-key","isActive":true}"#

    private func withBackupKey() -> Credentials {
        var credentials = Credentials(server: server, token: "old", username: "demo")
        credentials.backupKey = "backup-key"
        credentials.backupKeyID = 7
        return credentials
    }

    func testEnsureBackupKeyMakesOneKeyAfterPasswordLogin() async throws {
        let store = InMemoryCredentialStore()
        let session = SessionManager(store: store, transport: StubTransport([ok(authConfig), ok(loginReply), ok(createdKey)]))
        try await session.connect("https://x.io")
        try await session.login(username: "demo", password: "demodemo")

        await session.ensureBackupKey(name: "ByteCache on iPhone")
        XCTAssertEqual(store.load()?.backupKey, "backup-key")
        XCTAssertEqual(store.load()?.backupKeyID, 7)
        XCTAssertEqual(store.load()?.token, "t", "the login stays in use until it expires")
        XCTAssertFalse(session.isUsingBackupKey)

        await session.ensureBackupKey(name: "ByteCache on iPhone") // already has one: no request (none stubbed)
        XCTAssertEqual(store.load()?.backupKey, "backup-key")
    }

    func testRestoreWithExpiredLoginUsesTheBackupKey() async {
        let store = InMemoryCredentialStore(withBackupKey())
        let session = SessionManager(store: store, transport: StubTransport([status(403, invalidToken)]))
        await session.restore()
        guard case .signedIn(_, let user) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(user.username, "demo", "still shows who's signed in, not \"API key\"")
        XCTAssertTrue(session.isUsingBackupKey)
        XCTAssertEqual(session.client?.apiKey, "backup-key")
        XCTAssertNil(store.load()?.token)
    }

    func testRejectedLoginSwitchesToBackupKeyThenToSignIn() async {
        let store = InMemoryCredentialStore(withBackupKey())
        let verify = ok(#"{"valid":true,"user":{"id":2,"username":"demo"}}"#)
        let session = SessionManager(store: store, transport: StubTransport([verify, ok(authConfig)]))
        await session.restore()

        session.handleUnauthorized()
        guard case .signedIn = session.state else { return XCTFail("\(session.state)") }
        XCTAssertTrue(session.isUsingBackupKey)
        XCTAssertEqual(session.backupKeySwitches, 1)
        XCTAssertFalse(session.sessionExpired)

        // Other requests sent with the old login fail right after the switch: not the key's fault.
        session.handleUnauthorized()
        guard case .signedIn = session.state else { return XCTFail("a stale rejection signed out: \(session.state)") }

        session.backupKeyGracePeriod = .zero
        session.handleUnauthorized() // the backup key is rejected too (revoked): sign in again
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
        XCTAssertTrue(session.sessionExpired)
        XCTAssertNil(store.load()?.backupKey)
    }

    func testRestoreWithExpiredLoginAndNoBackupKeySaysItExpired() async {
        let store = InMemoryCredentialStore(Credentials(server: server, token: "old", username: "demo"))
        let session = SessionManager(store: store, transport: StubTransport([status(403, invalidToken), ok(authConfig)]))
        await session.restore()
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
        XCTAssertTrue(session.sessionExpired)
    }

    func testRestoreWithA403NotAboutTheLoginStaysSignedIn() async {
        // A proxy or VPN answering 403 while the network recovers isn't a reason to sign out.
        let store = InMemoryCredentialStore(Credentials(server: server, token: "t", username: "demo"))
        let session = SessionManager(store: store, transport: StubTransport([status(403, #"{"error":"Forbidden"}"#)]))
        await session.restore()
        guard case .signedIn(_, let user) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(user.username, "demo")
        XCTAssertEqual(store.load()?.token, "t")
    }

    func testBackupKeyIsSavedAndRead() throws {
        let credentials = withBackupKey()
        let decoded = try JSONDecoder().decode(Credentials.self, from: JSONEncoder().encode(credentials))
        XCTAssertEqual(decoded, credentials)
        XCTAssertNil(credentials.signedOut.backupKey)
    }
}

final class KeychainCredentialStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let store = KeychainCredentialStore(accessGroup: nil, service: "me.suryajs.bytecache.tests.\(UUID().uuidString)")
        let creds = Credentials(server: try ServerURL("https://x.io"), token: "t", username: "demo")
        do {
            try store.save(creds)
        } catch {
            throw XCTSkip("Keychain unavailable in this environment: \(error)")
        }
        defer { try? store.clear() }
        XCTAssertEqual(store.load(), creds)

        let updated = Credentials(server: creds.server, token: nil, username: "demo")
        try store.save(updated)
        XCTAssertEqual(store.load(), updated)

        try store.clear()
        XCTAssertNil(store.load())
    }
}

@MainActor
final class SessionChangeServerTests: XCTestCase {
    /// A saved server (here, or from iCloud) is kept: the server screen lists it, and removing it
    /// would also remove it from the user's other devices.
    func testChangeServerKeepsASavedServer() async throws {
        let server = try ServerURL("https://x.io")
        let store = InMemoryCredentialStore(Credentials(server: server, token: nil, username: "demo"))
        let config = #"{"authRequired":true}"#
        let session = SessionManager(store: store, transport: StubTransport(body: config))
        await session.restore()
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }

        session.changeServer()
        XCTAssertEqual(session.state, .needsServer)
        XCTAssertNil(store.load(), "no longer the active server")
        XCTAssertEqual(session.accounts.map(\.server), [server])
        XCTAssertTrue(session.removedAccountIDs.isEmpty)
    }

    /// A server typed in just now is dropped: "Use a Different Server" usually means a typo.
    func testChangeServerForgetsAServerJustTypedIn() async throws {
        let config = #"{"authRequired":true}"#
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport(body: config))
        try await session.connect("https://typo.example")
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }

        session.changeServer()
        XCTAssertEqual(session.state, .needsServer)
        XCTAssertTrue(session.accounts.isEmpty)
    }
}

final class FallbackCredentialStoreTests: XCTestCase {
    struct Failing: CredentialStore {
        struct Boom: Error {}
        func loadAll() -> AccountList { AccountList() }
        func saveAll(_ list: AccountList) throws { throw Boom() }
    }

    func testUsesFallbackWhenPrimaryCannotSave() throws {
        let fallback = InMemoryCredentialStore()
        let store = FallbackCredentialStore(primary: Failing(), fallback: fallback)
        let creds = Credentials(server: try ServerURL("https://x.io"), token: "t")
        try store.save(creds)
        XCTAssertEqual(store.load(), creds)
        try store.clear()
        XCTAssertNil(store.load())
    }

    func testPrefersPrimaryWhenItWorks() throws {
        let primary = InMemoryCredentialStore(), fallback = InMemoryCredentialStore()
        let store = FallbackCredentialStore(primary: primary, fallback: fallback)
        let creds = Credentials(server: try ServerURL("https://x.io"), token: "t")
        try store.save(creds)
        XCTAssertEqual(primary.load(), creds)
        XCTAssertNil(fallback.load())
    }
}
