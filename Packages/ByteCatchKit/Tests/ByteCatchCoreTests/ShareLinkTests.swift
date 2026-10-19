import XCTest
@testable import ByteCatchCore
import ByteCatchTestSupport

final class ShareLinkAPITests: XCTestCase {
    private func client(_ stub: StubTransport) throws -> APIClient {
        APIClient(server: try ServerURL("https://x.io/bs"), token: "t", transport: stub)
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testCreateSendsSnippetExpiryAndAuth() async throws {
        let stub = StubTransport(status: 201, body: #"{"id":"abc123","snippetId":5,"requiresAuth":true,"expiresIn":3600}"#)
        let id = try await client(stub).createShareLink(snippetID: 5, requiresAuth: true, expiresIn: 3600)
        XCTAssertEqual(id, "abc123")
        XCTAssertEqual(stub.last.url?.path, "/bs/api/share")
        let sent = try body(stub.last)
        XCTAssertEqual(sent["snippetId"] as? Int, 5)
        XCTAssertEqual(sent["requiresAuth"] as? Bool, true)
        XCTAssertEqual(sent["expiresIn"] as? Int, 3600)
    }

    func testNoExpiryLeavesItOut() async throws {
        let stub = StubTransport(status: 201, body: #"{"id":"z","snippetId":5,"requiresAuth":false}"#)
        _ = try await client(stub).createShareLink(snippetID: 5, requiresAuth: false, expiresIn: nil)
        XCTAssertNil(try body(stub.last)["expiresIn"])
    }

    func testListAndRevoke() async throws {
        let list = #"[{"id":"a1","snippet_id":5,"requires_auth":1,"expires_at":"2026-10-20 10:00:00","created_at":"2026-10-19 10:00:00","expired":0},{"id":"b2","snippet_id":5,"requires_auth":0,"expires_at":null,"created_at":"2026-10-18 09:00:00","expired":0}]"#
        let stub = StubTransport([.json(list), .json(#"{"success":true}"#)])
        let api = try client(stub)
        let links = try await api.shareLinks(snippetID: 5)
        XCTAssertEqual(stub.requests[0].url?.path, "/bs/api/share/snippet/5")
        XCTAssertEqual(links.map(\.id), ["a1", "b2"])
        XCTAssertTrue(links[0].requiresAuth)
        XCTAssertNotNil(links[0].expiresAt, "SQLite dates without a zone are UTC")
        XCTAssertNil(links[1].expiresAt)
        XCTAssertFalse(links[0].expired)
        try await api.revokeShareLink(id: "a1")
        XCTAssertEqual(stub.last.httpMethod, "DELETE")
        XCTAssertEqual(stub.last.url?.path, "/bs/api/share/a1")
    }

    func testLinkURLUsesServerPath() throws {
        let server = try ServerURL("https://x.io/bs")
        XCTAssertEqual(ShareLink.url(id: "abc", server: server).absoluteString, "https://x.io/bs/s/abc")
    }
}
