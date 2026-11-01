import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

/// ByteStash 1.6.0 / 1.6.1: login cookies, and `oidc_id` for single sign-on accounts.
@MainActor
final class ByteStash161Tests: XCTestCase {
    func testServerConnectionNeverKeepsOrSendsCookies() {
        let configuration = URLSession.byteStash.configuration
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
    }

    func testLeftoverLoginCookiesAreRemoved() throws {
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "bytecache-tests-\(UUID().uuidString)")
        func cookie(_ name: String) -> HTTPCookie {
            HTTPCookie(properties: [.name: name, .value: "v", .domain: "a.io", .path: "/"])!
        }
        for name in ["bytestash_token", "bytestash_id_token", "other"] { storage.setCookie(cookie(name)) }
        ByteStashCookies.removeLeftovers(from: storage)
        XCTAssertEqual(storage.cookies?.map(\.name), ["other"])
    }

    func testUserReadsTheSingleSignOnID() throws {
        let decode = { (json: String) in try JSONDecoder().decode(User.self, from: Data(json.utf8)) }
        XCTAssertEqual(try decode(#"{"id":1,"username":"a","oidc_id":"sub-1"}"#).oidcID, "sub-1")
        XCTAssertEqual(try decode(#"{"id":1,"username":"a","oidc_id":42}"#).oidcID, "42")
        XCTAssertFalse(try decode(#"{"id":1,"username":"a"}"#).usesSingleSignOn)
        XCTAssertFalse(try decode(#"{"id":1,"username":"a","oidc_id":null}"#).usesSingleSignOn)
        let user = try decode(#"{"id":1,"username":"a","oidc_id":"sub-1"}"#)
        XCTAssertEqual(try JSONDecoder().decode(User.self, from: JSONEncoder().encode(user)), user)
    }

    func testSingleSignOnIsRememberedEvenOnOlderServers() async throws {
        let store = InMemoryCredentialStore()
        let session = SessionManager(store: store, transport: StubTransport([
            .json(#"{"authRequired":true}"#), .json(#"{"enabled":true}"#), .json(TestJSON.verify),
        ]))
        try await session.connect("a.io")
        await session.loadSSO()
        // The verify answer has no oidc_id (ByteStash before 1.6.1).
        try await session.signIn(ssoToken: "jwt")
        guard case .signedIn(_, let user) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertTrue(user.usesSingleSignOn)

        // Next launch: the server is asked again and still doesn't say.
        let relaunched = SessionManager(store: store, transport: StubTransport([.json(TestJSON.verify)]))
        await relaunched.restore()
        guard case .signedIn(_, let again) = relaunched.state else { return XCTFail("\(relaunched.state)") }
        XCTAssertTrue(again.usesSingleSignOn, "Change Password stays hidden")
    }

    func testPasswordSignInIsNotSingleSignOn() async throws {
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport([
            .json(#"{"authRequired":true}"#), .json(#"{"token":"jwt","user":{"id":1,"username":"demo"}}"#),
        ]))
        try await session.connect("a.io")
        try await session.login(username: "demo", password: "pw")
        guard case .signedIn(_, let user) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertFalse(user.usesSingleSignOn)
    }
}
