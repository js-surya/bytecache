import XCTest
@testable import ByteCatchCore
import ByteCatchTestSupport

/// CP-11: edit a saved server's name and address.
@MainActor
final class EditServerTests: XCTestCase {
    private let config = #"{"authRequired":true,"disableInternalAccounts":false}"#
    private func ok(_ body: String) -> StubTransport.Reply { .response(status: 200, body: body, contentType: "application/json") }

    private func signedIn(_ replies: [StubTransport.Reply], extra: [Credentials] = []) async -> (SessionManager, InMemoryCredentialStore, StubTransport) {
        let main = Credentials(server: TestSession.server, token: "t", username: "demo")
        let store = InMemoryCredentialStore()
        try? store.saveAll(AccountList(accounts: [main] + extra, activeID: main.id))
        let transport = StubTransport([ok(TestJSON.verify)] + replies)
        let session = SessionManager(store: store, transport: transport)
        await session.restore()
        return (session, store, transport)
    }

    func testRenameKeepsLoginAndNeedsNoNetwork() async throws {
        let (session, store, transport) = await signedIn([])
        let id = try XCTUnwrap(session.activeAccountID)
        try await session.updateServer(id, name: "  Home NAS ", address: "x.io")
        XCTAssertEqual(store.loadAll().accounts.first?.name, "Home NAS")
        XCTAssertEqual(session.accounts.first?.name, "Home NAS")
        XCTAssertEqual(session.state, .signedIn(server: TestSession.server, user: User(id: 2, username: "demo")))
        XCTAssertEqual(transport.requests.count, 1, "only the launch verify")
        try await session.updateServer(id, name: "", address: "x.io")
        XCTAssertNil(session.accounts.first?.name, "blank name falls back to the address")
    }

    func testNewAddressIsCheckedAndLoginKept() async throws {
        let (session, store, transport) = await signedIn([ok(config), ok(TestJSON.verify)])
        let id = try XCTUnwrap(session.activeAccountID)
        try await session.updateServer(id, name: nil, address: "https://new.example.com/")
        let moved = try ServerURL("https://new.example.com")
        XCTAssertEqual(store.loadAll().accounts.first?.server, moved)
        XCTAssertEqual(store.loadAll().accounts.first?.token, "t", "same server under a new address keeps its login")
        XCTAssertEqual(session.state, .signedIn(server: moved, user: User(id: 2, username: "demo")))
        XCTAssertEqual(transport.requests.last?.url?.host(), "new.example.com")
    }

    func testUnreachableAddressChangesNothing() async throws {
        let (session, store, _) = await signedIn([.failure(URLError(.cannotFindHost))])
        let id = try XCTUnwrap(session.activeAccountID)
        do {
            try await session.updateServer(id, name: "x", address: "nowhere.invalid")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(store.loadAll().accounts.first?.server, TestSession.server)
            XCTAssertNil(store.loadAll().accounts.first?.name)
        }
    }

    func testAddressOfAnotherSavedServerIsRejected() async throws {
        let other = Credentials(server: try ServerURL("https://other.io"))
        let (session, _, _) = await signedIn([], extra: [other])
        let id = try XCTUnwrap(session.activeAccountID)
        do {
            try await session.updateServer(id, name: nil, address: "other.io")
            XCTFail("expected duplicate error")
        } catch {
            XCTAssertEqual(error, .duplicateServer)
        }
    }

    func testEditsTravelThroughICloud() throws {
        let id = UUID()
        var here = AccountList(accounts: [Credentials(id: id, server: try ServerURL("https://old.io"), token: "t")], activeID: id)
        let payload = ServerListPayload(servers: [SyncedServer(id: id, url: "https://new.io", name: "Work")], removed: [])
        here = here.merging(payload)
        XCTAssertEqual(here.accounts.first?.server, try ServerURL("https://new.io"))
        XCTAssertEqual(here.accounts.first?.name, "Work")
        XCTAssertEqual(here.accounts.first?.token, "t", "the login stays on this device")
        XCTAssertEqual(ServerListPayload(accounts: here.accounts, removed: []).servers.first?.name, "Work")
    }
}
