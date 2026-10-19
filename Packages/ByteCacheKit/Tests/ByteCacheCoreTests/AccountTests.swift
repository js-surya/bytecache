import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

final class APIKeyClientTests: XCTestCase {
    func testAPIKeySentInsteadOfToken() async throws {
        let stub = StubTransport(body: #"{"categories":[],"languages":[]}"#)
        let client = APIClient(server: try ServerURL("https://x.io"), token: nil, apiKey: "k123", transport: stub)
        _ = try await client.metadata()
        XCTAssertEqual(stub.last.value(forHTTPHeaderField: "x-api-key"), "k123")
        XCTAssertNil(stub.last.value(forHTTPHeaderField: "bytestashauth"))
    }

    func testCredentialsMakeClient() throws {
        let server = try ServerURL("https://x.io")
        XCTAssertNil(Credentials(server: server).makeClient(), "no login yet")
        XCTAssertEqual(Credentials(server: server, token: "t").makeClient()?.token, "t")
        XCTAssertEqual(Credentials(server: server, apiKey: "k").makeClient()?.apiKey, "k")
    }
}

final class AccountStoreTests: XCTestCase {
    func testLegacySingleCredentialsDecodeIntoList() throws {
        let legacy = #"{"server":{"base":"https://x.io"},"token":"t","username":"demo"}"#
        let list = try AccountList.decode(Data(legacy.utf8))
        XCTAssertEqual(list.accounts.count, 1)
        XCTAssertEqual(list.active?.token, "t")
        XCTAssertEqual(list.active?.username, "demo")
    }

    func testLegacyLoginKeepsTheSameIDAcrossReads() throws {
        let legacy = Data(#"{"server":{"base":"https://x.io"},"token":"t","username":"demo"}"#.utf8)
        XCTAssertEqual(try AccountList.decode(legacy).active?.id, try AccountList.decode(legacy).active?.id)

        let store = InMemoryCredentialStore()
        try store.saveAll(try AccountList.decode(legacy))
        var migrated = try XCTUnwrap(try AccountList.decode(legacy).active)
        migrated.username = "demo2"
        try store.save(migrated)
        XCTAssertEqual(store.loadAll().accounts.count, 1, "upgrading must not duplicate the login")
    }

    func testExactDuplicatesAreMergedOnRead() throws {
        let server = try ServerURL("https://x.io")
        let a = Credentials(server: server, token: "t", username: "demo")
        let copy = Credentials(server: server, token: "t", username: "demo")
        let other = Credentials(server: server, apiKey: "k")
        let data = try JSONEncoder().encode(AccountList(accounts: [a, copy, other], activeID: copy.id))
        let list = try AccountList.decode(data)
        XCTAssertEqual(list.accounts.map(\.id), [copy.id, other.id], "keeps the active one of each duplicate")
        XCTAssertEqual(list.activeID, copy.id)
    }

    func testSaveAddsAndActivatesClearRemovesActive() throws {
        let store = InMemoryCredentialStore()
        let a = Credentials(server: try ServerURL("https://a.io"), token: "1")
        let b = Credentials(server: try ServerURL("https://b.io"), apiKey: "k")
        try store.save(a)
        try store.save(b)
        XCTAssertEqual(store.loadAll().accounts.map(\.id), [a.id, b.id])
        XCTAssertEqual(store.load()?.id, b.id)

        var updated = a
        updated.token = "2"
        try store.save(updated)
        XCTAssertEqual(store.loadAll().accounts.count, 2, "same id updates in place")
        XCTAssertEqual(store.load()?.token, "2")

        try store.clear()
        XCTAssertEqual(store.loadAll().accounts.map(\.id), [b.id])
        XCTAssertNil(store.load(), "no active account after clearing it")
    }
}

@MainActor
final class MultiServerSessionTests: XCTestCase {
    private let a = try! ServerURL("https://a.io")
    private let b = try! ServerURL("https://b.io")
    private let config = #"{"authRequired":true}"#
    private let verify = #"{"valid":true,"user":{"id":2,"username":"demo"}}"#
    private let meta = #"{"categories":[],"languages":[]}"#

    func testAPIKeyLogin() async throws {
        let store = InMemoryCredentialStore()
        let stub = StubTransport([.json(config), .json(meta)])
        let session = SessionManager(store: store, transport: stub)
        try await session.connect("a.io")
        try await session.loginWithAPIKey("  k123 ")
        XCTAssertEqual(session.state, .signedIn(server: a, user: User(id: 0, username: SessionManager.apiKeyUserName)))
        XCTAssertEqual(stub.last.url?.path, "/api/snippets/metadata")
        XCTAssertEqual(store.load()?.apiKey, "k123")
        XCTAssertNil(store.load()?.token)
        XCTAssertEqual(session.client?.apiKey, "k123")
    }

    func testBadAPIKeyStaysOnLogin() async throws {
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport([.json(config), .json("{}", status: 401)]))
        try await session.connect("a.io")
        do {
            try await session.loginWithAPIKey("bad")
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .unauthorized)
        }
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
    }

    func testRestoreWithAPIKeyChecksMetadata() async {
        let store = InMemoryCredentialStore(Credentials(server: a, apiKey: "k"))
        let stub = StubTransport([.json(meta)])
        let session = SessionManager(store: store, transport: stub)
        await session.restore()
        guard case .signedIn = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(stub.last.url?.path, "/api/snippets/metadata")
    }

    func testAddSecondServerKeepsFirstAndSwitchBack() async throws {
        let store = InMemoryCredentialStore(Credentials(server: a, token: "t", username: "demo"))
        let stub = StubTransport([.json(verify), .json(config), .json(#"{"token":"t2","user":{"id":3,"username":"me"}}"#), .json(verify)])
        let session = SessionManager(store: store, transport: stub)
        await session.restore()
        let first = try XCTUnwrap(session.activeAccountID)

        session.addServer()
        XCTAssertEqual(session.state, .needsServer)
        XCTAssertTrue(session.canCancelAddServer)
        try await session.connect("b.io")
        try await session.login(username: "me", password: "pw")
        XCTAssertEqual(session.accounts.map(\.server), [a, b])
        guard case .signedIn(let now, _) = session.state else { return XCTFail() }
        XCTAssertEqual(now, b)

        await session.switchTo(first)
        guard case .signedIn(let back, _) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(back, a)
        XCTAssertEqual(store.load()?.server, a, "active account persisted")
    }

    func testCancelAddServerReturnsToPrevious() async {
        let store = InMemoryCredentialStore(Credentials(server: a, token: "t", username: "demo"))
        let session = SessionManager(store: store, transport: StubTransport([.json(verify)]))
        await session.restore()
        session.addServer()
        await session.cancelAddServer()
        guard case .signedIn(let server, _) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(server, a)
    }

    func testRemovingActiveAccountSwitchesToRemaining() async throws {
        let store = InMemoryCredentialStore()
        let first = Credentials(server: a, token: "t", username: "demo")
        let second = Credentials(server: b, apiKey: "k")
        try store.save(first)
        try store.save(second)
        let session = SessionManager(store: store, transport: StubTransport([.json(meta), .json(verify)]))
        await session.restore()
        await session.removeAccount(second.id)
        XCTAssertEqual(session.accounts.map(\.id), [first.id])
        guard case .signedIn(let server, _) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(server, a)

        await session.removeAccount(first.id)
        XCTAssertEqual(session.state, .needsServer)
        XCTAssertFalse(session.canCancelAddServer)
    }

    func testSignOutDropsAPIKeyButKeepsServer() async throws {
        let store = InMemoryCredentialStore(Credentials(server: a, apiKey: "k"))
        let session = SessionManager(store: store, transport: StubTransport([.json(meta), .json(config)]))
        await session.restore()
        session.signOut()
        XCTAssertNil(store.load()?.apiKey)
        XCTAssertEqual(store.load()?.server, a)
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
    }
}
