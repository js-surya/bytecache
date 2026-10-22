import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

/// CP-75: create an account when the server allows it, and be signed in straight away.
@MainActor
final class RegisterTests: XCTestCase {
    private let open = #"{"authRequired":true,"allowNewAccounts":true,"hasUsers":true}"#
    private let firstUser = #"{"authRequired":true,"allowNewAccounts":false,"hasUsers":false}"#
    private let closed = #"{"authRequired":true,"allowNewAccounts":false,"hasUsers":true}"#
    private let created = #"{"token":"t","user":{"id":7,"username":"new"}}"#

    func testRegisterPostsTheLogin() async throws {
        let stub = StubTransport(body: created)
        let result = try await APIClient(server: try ServerURL("https://a.io"), token: nil, transport: stub)
            .register(username: "new", password: "secret")
        XCTAssertEqual(result.token, "t")
        XCTAssertEqual(stub.last.httpMethod, "POST")
        XCTAssertEqual(stub.last.url?.path, "/api/auth/register")
        let json = try JSONSerialization.jsonObject(with: stub.last.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(json?["username"] as? String, "new")
        XCTAssertEqual(json?["password"] as? String, "secret")
    }

    func testCreatingAnAccountSignsIn() async throws {
        let session = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport([.json(open), .json(created)]))
        try await session.connect("a.io")
        XCTAssertTrue(session.canCreateAccount)
        try await session.register(username: "new", password: "secret")
        guard case .signedIn(_, let user) = session.state else { return XCTFail("\(session.state)") }
        XCTAssertEqual(user.username, "new")
    }

    func testOfferedOnlyWhenTheServerAllowsIt() async throws {
        let first = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport([.json(firstUser)]))
        try await first.connect("a.io")
        XCTAssertTrue(first.canCreateAccount, "a server with no users lets the first one sign up")

        let shut = SessionManager(store: InMemoryCredentialStore(), transport: StubTransport([.json(closed)]))
        try await shut.connect("a.io")
        XCTAssertFalse(shut.canCreateAccount)
    }
}
