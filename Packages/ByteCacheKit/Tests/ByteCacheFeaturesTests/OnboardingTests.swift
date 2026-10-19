import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

@MainActor
final class OnboardingTests: XCTestCase {
    private let config = #"{"authRequired":true,"allowNewAccounts":false,"hasUsers":true,"disableAccounts":false,"disableInternalAccounts":false}"#
    private let login = #"{"token":"t","user":{"id":2,"username":"demo"}}"#

    private func model(_ replies: [StubTransport.Reply]) -> (OnboardingModel, SessionManager) {
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport(replies))
        return (OnboardingModel(session: session), session)
    }

    private func ok(_ body: String) -> StubTransport.Reply { .response(status: 200, body: body, contentType: "application/json") }

    func testDemoServerButtonFillsDemoAddress() {
        let (m, _) = model([])
        m.useDemoServer()
        XCTAssertEqual(m.serverText, "https://bytestash-demo.pikapod.net")
        XCTAssertEqual(m.username, "demo")
        XCTAssertEqual(m.password, "demodemo")
    }

    func testConnectDisabledForBlankAddress() {
        let (m, _) = model([])
        m.serverText = "   "
        XCTAssertFalse(m.canConnect)
        m.serverText = "nas.local"
        XCTAssertTrue(m.canConnect)
    }

    func testConnectThenLoginSignsIn() async {
        let (m, session) = model([ok(config), ok(login)])
        m.serverText = "x.io"
        await m.connect()
        XCTAssertNil(m.errorMessage)
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }

        m.username = "demo"; m.password = "demodemo"
        await m.login()
        guard case .signedIn = session.state else { return XCTFail("\(session.state)") }
        XCTAssertFalse(m.isWorking)
    }

    func testLoginDisabledWithEmptyUsernameOrPassword() {
        let (m, _) = model([])
        m.username = ""; m.password = "x"
        XCTAssertFalse(m.canLogin)
        m.username = "demo"; m.password = ""
        XCTAssertFalse(m.canLogin)
        m.password = "x"
        XCTAssertTrue(m.canLogin)
    }

    func testConnectErrorsShowFriendlyCopy() async {
        let (m, _) = model([.response(status: 200, body: "<html>", contentType: "text/html")])
        m.serverText = "x.io"
        await m.connect()
        XCTAssertEqual(m.errorMessage, "That address doesn't look like a ByteStash server.")
    }

    func testErrorCopyForEveryCase() {
        XCTAssertEqual(ErrorText.message(for: .offline), "You're offline. Check your connection and try again.")
        XCTAssertEqual(ErrorText.message(for: .notByteStash), "That address doesn't look like a ByteStash server.")
        XCTAssertEqual(ErrorText.message(for: .invalidServer), "Enter a server address like https://bytestash.example.com.")
        XCTAssertEqual(ErrorText.message(for: .unauthorized), "Wrong username or password, or your session expired.")
        XCTAssertEqual(ErrorText.message(for: .forbidden("Account has been deactivated")), "Account has been deactivated")
        XCTAssertEqual(ErrorText.message(for: .forbidden(nil)), "The server refused this request.")
        XCTAssertEqual(ErrorText.message(for: .notFound), "That snippet no longer exists on the server.")
        XCTAssertEqual(ErrorText.message(for: .server(status: 500, message: "Internal server error")), "Server error (500): Internal server error")
        XCTAssertEqual(ErrorText.message(for: .decoding("x")), "The server sent a response ByteCache didn't understand.")
    }

    func testBadPasswordShowsMessageAndStaysOnLogin() async {
        let (m, session) = model([ok(config), .response(status: 401, body: "{}", contentType: "application/json")])
        m.serverText = "x.io"
        await m.connect()
        m.username = "demo"; m.password = "nope"
        await m.login()
        XCTAssertEqual(m.errorMessage, "Wrong username or password, or your session expired.")
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
    }

    func testAPIKeyModeNeedsOnlyAKey() {
        let (m, _) = model([])
        m.method = .apiKey
        m.username = ""; m.password = ""
        XCTAssertFalse(m.canLogin)
        m.apiKey = "  "
        XCTAssertFalse(m.canLogin)
        m.apiKey = "k123"
        XCTAssertTrue(m.canLogin)
    }

    func testAPIKeyLoginSignsInAndClearsField() async {
        let (m, session) = model([ok(config), ok(#"{"categories":[],"languages":[]}"#)])
        m.serverText = "x.io"
        await m.connect()
        m.method = .apiKey
        m.apiKey = "k123"
        await m.login()
        guard case .signedIn = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(m.apiKey, "")
    }

    func testRejectedAPIKeyHasItsOwnMessage() async {
        let (m, _) = model([ok(config), .response(status: 401, body: "{}", contentType: "application/json")])
        m.serverText = "x.io"
        await m.connect()
        m.method = .apiKey
        m.apiKey = "bad"
        await m.login()
        XCTAssertEqual(m.errorMessage, "That API key wasn't accepted. Create one in ByteStash under Settings → API Keys.")
    }

    func testConnectClearsOldFieldsForTheNextServer() async {
        let (m, _) = model([ok(config)])
        m.username = "old"; m.password = "pw"; m.apiKey = "k"
        m.serverText = "x.io"
        await m.connect()
        XCTAssertEqual(m.password, "")
        XCTAssertEqual(m.apiKey, "")
    }
}
