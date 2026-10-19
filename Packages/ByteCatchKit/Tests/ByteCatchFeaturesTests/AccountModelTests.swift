import XCTest
import ByteCatchCore
import ByteCatchTestSupport
@testable import ByteCatchFeatures

@MainActor
final class AccountModelTests: XCTestCase {
    private let keysJSON = #"[{"id":1,"name":"Laptop","created_at":"2026-10-18 10:00:00Z","last_used_at":null,"is_active":1}]"#

    func testAPIKeySessionCannotManage() async throws {
        let store = InMemoryCredentialStore(Credentials(server: try ServerURL("https://x.io"), apiKey: "k"))
        let session = SessionManager(store: store, transport: StubTransport([.json(#"{"categories":[],"languages":[]}"#)]))
        await session.restore()
        XCTAssertFalse(AccountModel(session: session).canManage)
    }

    func testLoadCreateDeleteKeys() async {
        let created = #"{"id":2,"key":"secret-abc","name":"Phone","created_at":"2026-10-19T01:00:00.000Z","is_active":true}"#
        let (session, transport) = await TestSession.signedIn([.json(keysJSON), .json(#"{"authRequired":true}"#), .json(created, status: 201), .json(#"{"sucess":true}"#)])
        let model = AccountModel(session: session)
        XCTAssertTrue(model.canManage)
        await model.loadKeys()
        XCTAssertEqual(model.keys.map(\.name), ["Laptop"])

        await model.createKey(name: "  Phone ")
        XCTAssertEqual(model.newKey?.key, "secret-abc")
        XCTAssertEqual(model.keys.map(\.name), ["Phone", "Laptop"])
        model.dismissNewKey()
        XCTAssertNil(model.newKey, "the secret is shown once")

        await model.deleteKey(model.keys[1])
        XCTAssertEqual(model.keys.map(\.name), ["Phone"])
        XCTAssertEqual(transport.last.url?.path, "/api/keys/1")
    }

    func testEmptyKeyNameIsRejected() async {
        let (session, transport) = await TestSession.signedIn([])
        let model = AccountModel(session: session)
        let before = transport.requests.count
        await model.createKey(name: "   ")
        XCTAssertEqual(model.error, "Give the key a name.")
        XCTAssertEqual(transport.requests.count, before)
    }

    func testPasswordValidation() async {
        let (session, _) = await TestSession.signedIn([])
        let model = AccountModel(session: session)
        model.currentPassword = "old"
        model.newPassword = "newpass12"
        model.confirmPassword = "newpass13"
        XCTAssertFalse(model.canChangePassword)
        XCTAssertEqual(model.passwordProblem, "The new passwords don't match.")
        model.confirmPassword = "newpass12"
        XCTAssertTrue(model.canChangePassword)
        XCTAssertNil(model.passwordProblem)
        model.newPassword = "old"; model.confirmPassword = "old"
        XCTAssertEqual(model.passwordProblem, "Choose a password different from the current one.")
    }

    func testChangePasswordSuccessClearsFields() async {
        let (session, transport) = await TestSession.signedIn([.json(#"{"success":true}"#)])
        let model = AccountModel(session: session)
        model.currentPassword = "old"; model.newPassword = "newpass12"; model.confirmPassword = "newpass12"
        await model.changePassword()
        XCTAssertTrue(model.passwordChanged)
        XCTAssertEqual(model.currentPassword, "")
        XCTAssertEqual(transport.last.url?.path, "/api/auth/change-password")
    }

    func testServerMessageShownAsIs() async {
        let (session, _) = await TestSession.signedIn([.json(#"{"error":"Current password is incorrect"}"#, status: 400)])
        let model = AccountModel(session: session)
        model.currentPassword = "wrong"; model.newPassword = "newpass12"; model.confirmPassword = "newpass12"
        await model.changePassword()
        XCTAssertFalse(model.passwordChanged)
        XCTAssertEqual(model.error, "Current password is incorrect")
        XCTAssertEqual(model.currentPassword, "wrong", "kept so the user can fix it")
    }
}
