import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

final class SyncedServerTests: XCTestCase {
    func testExportNeverContainsSecrets() throws {
        let a = Credentials(server: try ServerURL("https://a.io"), token: "secret-token", username: "demo")
        let b = Credentials(server: try ServerURL("https://b.io/bs"), apiKey: "secret-key")
        let payload = try ServerListPayload(accounts: [a, b], removed: []).encoded()
        let text = String(decoding: payload, as: UTF8.self)
        XCTAssertFalse(text.contains("secret-token"))
        XCTAssertFalse(text.contains("secret-key"))
        XCTAssertFalse(text.contains("demo"), "user names stay on the device too")
        let decoded = try ServerListPayload.decode(payload)
        XCTAssertEqual(decoded.servers.map(\.url), ["https://a.io", "https://b.io/bs"])
        XCTAssertEqual(decoded.servers.map(\.id), [a.id, b.id])
    }
}

final class ServerMergeTests: XCTestCase {
    private let a = try! ServerURL("https://a.io")
    private let b = try! ServerURL("https://b.io")
    private let c = try! ServerURL("https://c.io")

    func testIncomingServersAreAddedSignedOutWithoutChangingActive() {
        let local = Credentials(server: a, token: "t")
        let list = AccountList(accounts: [local], activeID: local.id)
        let remoteB = SyncedServer(id: UUID(), url: b.base.absoluteString)
        let merged = list.merging(ServerListPayload(servers: [remoteB], removed: []))
        XCTAssertEqual(merged.accounts.map(\.server), [a, b])
        XCTAssertEqual(merged.accounts[1].id, remoteB.id)
        XCTAssertFalse(merged.accounts[1].isSignedIn)
        XCTAssertEqual(merged.activeID, local.id)
    }

    func testSameAddressIsNotDuplicated() {
        let local = Credentials(server: a, token: "t")
        let list = AccountList(accounts: [local], activeID: local.id)
        let merged = list.merging(ServerListPayload(servers: [SyncedServer(id: UUID(), url: "https://a.io/")], removed: []))
        XCTAssertEqual(merged.accounts.count, 1)
        XCTAssertEqual(merged.accounts[0].token, "t")
    }

    func testRemovedServersDisappearEverywhere() {
        let x = Credentials(server: a, token: "t"), y = Credentials(server: b)
        let list = AccountList(accounts: [x, y], activeID: x.id)
        let merged = list.merging(ServerListPayload(servers: [], removed: [y.id]))
        XCTAssertEqual(merged.accounts.map(\.id), [x.id])
        let activeGone = list.merging(ServerListPayload(servers: [], removed: [x.id]))
        XCTAssertNil(activeGone.activeID)
    }

    func testInvalidRemoteAddressesAreIgnored() {
        let merged = AccountList().merging(ServerListPayload(servers: [SyncedServer(id: UUID(), url: "ftp://nope")], removed: []))
        XCTAssertTrue(merged.accounts.isEmpty)
    }
}

@MainActor
final class SessionSyncTests: XCTestCase {
    func testApplyingRemoteServersUpdatesAccountsAndKeepsSession() async throws {
        let a = try ServerURL("https://a.io")
        let store = InMemoryCredentialStore(Credentials(server: a, token: "t", username: "demo"))
        let session = SessionManager(store: store, transport: StubTransport([.json(#"{"valid":true,"user":{"id":2,"username":"demo"}}"#)]))
        await session.restore()
        let remote = SyncedServer(id: UUID(), url: "https://b.io")
        await session.applySyncedServers(ServerListPayload(servers: [remote], removed: []))
        XCTAssertEqual(session.accounts.count, 2)
        guard case .signedIn(let server, _) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(server, a)
        XCTAssertEqual(store.loadAll().accounts.count, 2, "persisted")
    }

    func testRemovingTheActiveServerRemotelySwitchesAway() async throws {
        let a = try ServerURL("https://a.io")
        let first = Credentials(server: a, token: "t")
        let store = InMemoryCredentialStore(first)
        let session = SessionManager(store: store, transport: StubTransport([.json(#"{"valid":true,"user":{"id":2,"username":"demo"}}"#)]))
        await session.restore()
        await session.applySyncedServers(ServerListPayload(servers: [], removed: [first.id]))
        XCTAssertEqual(session.state, .needsServer)
        XCTAssertTrue(session.accounts.isEmpty)
    }

    func testLocalRemovalIsRecordedForSync() async throws {
        let first = Credentials(server: try ServerURL("https://a.io"), token: "t")
        let session = SessionManager(store: InMemoryCredentialStore(first), transport: StubTransport([.json(#"{"valid":true,"user":{"id":2,"username":"demo"}}"#)]))
        await session.restore()
        await session.removeAccount(first.id)
        XCTAssertEqual(session.removedAccountIDs, [first.id])
    }
}
