import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

/// CP-72: sign in through the server's single sign-on.
@MainActor
final class SingleSignOnTests: XCTestCase {
    private let server = try! ServerURL("https://snip.example.com/stash")

    func testReadsWhereTheFlowHasGot() {
        let start = SingleSignOn.startURL(for: server)
        XCTAssertEqual(start.absoluteString, "https://snip.example.com/stash/api/auth/oidc/auth")
        XCTAssertNil(SingleSignOn.step(for: start, server: server))
        XCTAssertNil(SingleSignOn.step(for: URL(string: "https://id.example.com/authorize?x=1")!, server: server), "the provider's pages")
        XCTAssertNil(SingleSignOn.step(for: URL(string: "https://snip.example.com/stash/api/auth/oidc/callback?code=1")!, server: server))
        XCTAssertEqual(SingleSignOn.step(for: URL(string: "https://snip.example.com/stash/auth/callback")!, server: server), .finished)
        XCTAssertNil(SingleSignOn.step(for: URL(string: "https://evil.example.org/auth/callback")!, server: server), "only this server")
    }

    func testErrorsSayWhatWentWrong() {
        let disabled = URL(string: "https://snip.example.com/login?error=registration_disabled")!
        XCTAssertEqual(SingleSignOn.step(for: disabled, server: server),
                       .failed("This server doesn't allow new accounts, so it can't create one for this sign-in."))
        let denied = URL(string: "https://snip.example.com/login?error=provider_error&message=Authorization%20denied%20by%20identity%20provider")!
        XCTAssertEqual(SingleSignOn.step(for: denied, server: server), .failed("Authorization denied by identity provider"))
    }

    func testButtonTitle() {
        XCTAssertEqual(SSOConfig(enabled: true, displayName: "Authentik").buttonTitle, "Sign In with Authentik")
        XCTAssertEqual(SSOConfig(enabled: true, displayName: "Single Sign-On").buttonTitle, "Sign In with Single Sign-On")
    }

    func testSSOOnlyServerOffersSingleSignOn() async throws {
        let config = #"{"authRequired":true,"disableInternalAccounts":true}"#
        let sso = #"{"enabled":true,"displayName":"Pocket ID"}"#
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport([.json(config), .json(sso)]))
        try await session.connect("a.io")
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(session.sso, SSOConfig(enabled: true, displayName: "Pocket ID"))
    }

    func testSSOOnlyServerWithoutSSOStillSaysSo() async {
        let config = #"{"authRequired":true,"disableInternalAccounts":true}"#
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport([.json(config), .json(#"{"enabled":false}"#)]))
        do {
            try await session.connect("a.io")
            XCTFail("should refuse")
        } catch {
            XCTAssertEqual(error, .forbidden(SessionManager.ssoOnlyMessage))
        }
    }

    func testTokenFromSingleSignOnSignsIn() async throws {
        let config = #"{"authRequired":true}"#
        let session = SessionManager(store: InMemoryCredentialStore(),
                                     transport: StubTransport([.json(config), .json(#"{"enabled":true}"#), .json(TestJSON.verify)]))
        try await session.connect("a.io")
        await session.loadSSO()
        XCTAssertEqual(session.sso?.enabled, true)
        try await session.signIn(ssoToken: "jwt")
        guard case .signedIn(_, let user) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(user.username, "demo")
        XCTAssertEqual(session.client?.token, "jwt")
    }
}
