import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

final class APIClientTests: XCTestCase {
    private let server = try! ServerURL("https://x.io")

    private func client(_ transport: StubTransport, token: String? = "abc", server: ServerURL? = nil) -> APIClient {
        APIClient(server: server ?? self.server, token: token, transport: transport)
    }

    private func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let snippetJSON = """
    {"id":7,"title":"t","description":"","updated_at":"2026-10-18 00:45:14Z","expiry_date":null,
     "is_public":1,"is_pinned":0,"is_favorite":0,"categories":[],"share_count":0,
     "fragments":[{"id":1,"file_name":"main","code":"x","language":"swift","position":0}]}
    """

    func testSendsAuthHeader() async throws {
        let stub = StubTransport(body: #"{"categories":[],"languages":[]}"#)
        _ = try await client(stub, token: "abc").metadata()
        XCTAssertEqual(stub.last.value(forHTTPHeaderField: "bytestashauth"), "Bearer abc")

        _ = try await client(stub, token: nil).metadata()
        XCTAssertNil(stub.last.value(forHTTPHeaderField: "bytestashauth"))
    }

    func testLoginPostsJSONAndParsesToken() async throws {
        let stub = StubTransport(body: #"{"token":"t","user":{"id":2,"username":"demo","is_admin":false}}"#)
        let result = try await client(stub, token: nil).login(username: "demo", password: "demodemo")
        XCTAssertEqual(result.token, "t")
        XCTAssertEqual(result.user.username, "demo")
        XCTAssertEqual(stub.last.httpMethod, "POST")
        XCTAssertEqual(stub.last.url?.path, "/api/auth/login")
        XCTAssertEqual(stub.last.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try bodyJSON(stub.last)
        XCTAssertEqual(json["username"] as? String, "demo")
        XCTAssertEqual(json["password"] as? String, "demodemo")
    }

    func testVerifyReturnsUser() async throws {
        let stub = StubTransport(body: #"{"valid":true,"user":{"id":2,"username":"demo","is_admin":false}}"#)
        let user = try await client(stub).verify()
        XCTAssertEqual(user.id, 2)
        XCTAssertEqual(stub.last.url?.path, "/api/auth/verify")
    }

    func testStatusMapping() async {
        func error(_ stub: StubTransport) async -> APIError? {
            do { _ = try await client(stub).snippet(id: 1) } catch { return error }
            return nil
        }
        let unauthorized = await error(StubTransport(status: 401, body: #"{"valid":false}"#))
        XCTAssertEqual(unauthorized, .unauthorized)
        let forbidden = await error(StubTransport(status: 403, body: #"{"error":"Account has been deactivated"}"#))
        XCTAssertEqual(forbidden, .forbidden("Account has been deactivated"))
        let notFound = await error(StubTransport(status: 404, body: "{}"))
        XCTAssertEqual(notFound, .notFound)
        let failure = await error(StubTransport(status: 500, body: #"{"error":"Internal server error"}"#))
        XCTAssertEqual(failure, .server(status: 500, message: "Internal server error"))
        let offline = await error(StubTransport([.failure(URLError(.notConnectedToInternet))]))
        XCTAssertEqual(offline, .offline)
        let timedOut = await error(StubTransport([.failure(URLError(.timedOut))]))
        XCTAssertEqual(timedOut, .offline)
    }

    func testAuthConfigOnNonByteStashHTMLReturnsNotByteStash() async {
        let stub = StubTransport(body: "<html></html>", contentType: "text/html; charset=utf-8")
        do {
            _ = try await client(stub).authConfig()
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .notByteStash)
        }
    }

    func testBadJSONMapsToDecodingError() async {
        let stub = StubTransport(body: #"{"unexpected":true}"#)
        do {
            _ = try await client(stub).authConfig()
            XCTFail("expected failure")
        } catch {
            guard case .decoding = error else { return XCTFail("got \(error)") }
        }
    }

    func testPinFavoriteRecycleRestoreDelete() async throws {
        let stub = StubTransport(body: "{}")
        let api = client(stub)

        try await api.setPinned(id: 7, true)
        XCTAssertEqual(stub.last.httpMethod, "PATCH")
        XCTAssertEqual(stub.last.url?.path, "/api/snippets/7/pin")
        XCTAssertEqual(try bodyJSON(stub.last)["is_pinned"] as? Bool, true)

        try await api.setFavorite(id: 7, false)
        XCTAssertEqual(stub.last.url?.path, "/api/snippets/7/favorite")
        XCTAssertEqual(try bodyJSON(stub.last)["is_favorite"] as? Bool, false)

        try await api.recycle(id: 7)
        XCTAssertEqual(stub.last.httpMethod, "PATCH")
        XCTAssertEqual(stub.last.url?.path, "/api/snippets/7/recycle")
        XCTAssertNil(stub.last.httpBody)

        try await api.restore(id: 7)
        XCTAssertEqual(stub.last.httpMethod, "PATCH")
        XCTAssertEqual(stub.last.url?.path, "/api/snippets/7/restore")
        XCTAssertNil(stub.last.httpBody)

        try await api.delete(id: 7)
        XCTAssertEqual(stub.last.httpMethod, "DELETE")
        XCTAssertEqual(stub.last.url?.path, "/api/snippets/7")
    }

    func testSubPathServer() async throws {
        let stub = StubTransport(body: #"{"data":[],"pagination":{"total":0,"offset":0,"limit":50,"hasMore":false}}"#)
        let api = client(stub, server: try ServerURL("https://x.io/b"))
        _ = try await api.snippets(SnippetQuery(search: "curl"))
        let url = try XCTUnwrap(stub.last.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://x.io/b/api/snippets?"), url)
        XCTAssertTrue(url.contains("search=curl"), url)
    }

    func testCreateAndUpdateSendFullDraftIncludingIsPublic() async throws {
        let stub = StubTransport(body: snippetJSON)
        let api = client(stub)
        let draft = SnippetDraft(
            title: "t", description: "d", categories: ["a"],
            fragments: [FragmentDraft(fileName: "main", code: "x", language: "swift")], isPublic: true
        )

        let created = try await api.create(draft)
        XCTAssertEqual(created.id, 7)
        XCTAssertEqual(stub.last.httpMethod, "POST")
        XCTAssertEqual(stub.last.url?.path, "/api/snippets")

        _ = try await api.update(id: 7, draft)
        XCTAssertEqual(stub.last.httpMethod, "PUT")
        XCTAssertEqual(stub.last.url?.path, "/api/snippets/7")
        let json = try bodyJSON(stub.last)
        XCTAssertEqual(json["is_public"] as? Int, 1)
        XCTAssertEqual(json["categories"] as? [String], ["a"])
        XCTAssertEqual((json["fragments"] as? [[String: Any]])?.count, 1)
    }

    func testAnonymousLoginWithoutUserFallsBack() async throws {
        let stub = StubTransport(body: #"{"token":"anon"}"#)
        let result = try await client(stub, token: nil).anonymousLogin()
        XCTAssertEqual(result.token, "anon")
        XCTAssertEqual(stub.last.url?.path, "/api/auth/anonymous")
        XCTAssertEqual(stub.last.httpMethod, "POST")
    }
}

/// Hits the public demo server. Only runs with `BYTECACHE_LIVE=1`.
final class LiveDemoTests: XCTestCase {
    func testLoginAndFetchOneSnippet() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BYTECACHE_LIVE"] == "1")
        let server = try ServerURL("https://bytestash-demo.pikapod.net")
        let login = try await APIClient(server: server, token: nil).login(username: "demo", password: "demodemo")
        let api = APIClient(server: server, token: login.token)
        _ = try await api.verify()
        let page = try await api.snippets(SnippetQuery(limit: 1))
        XCTAssertEqual(page.snippets.count, 1)
        _ = try await api.metadata()
    }
}
