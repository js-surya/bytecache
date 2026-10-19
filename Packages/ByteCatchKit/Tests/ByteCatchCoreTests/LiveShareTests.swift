import XCTest
@testable import ByteCatchCore

/// Runs only with BYTECATCH_LIVE=1 against the public demo: creates a 1-hour link and revokes it.
final class LiveShareTests: XCTestCase {
    func testCreateListRevokeOnDemo() async throws {
        guard ProcessInfo.processInfo.environment["BYTECATCH_LIVE"] == "1" else { throw XCTSkip("Set BYTECATCH_LIVE=1") }
        let server = try ServerURL("https://bytestash-demo.pikapod.net")
        let login = try await APIClient(server: server, token: nil).login(username: "demo", password: "demodemo")
        let client = APIClient(server: server, token: login.token)
        let snippet = try await client.snippets(SnippetQuery(limit: 1)).snippets[0]
        let id = try await client.createShareLink(snippetID: snippet.id, requiresAuth: false, expiresIn: 3600)
        let links = try await client.shareLinks(snippetID: snippet.id)
        let link = try XCTUnwrap(links.first { $0.id == id })
        XCTAssertNotNil(link.expiresAt)
        XCTAssertFalse(link.expired)
        try await client.revokeShareLink(id: id)
        let after = try await client.shareLinks(snippetID: snippet.id)
        XCTAssertFalse(after.contains { $0.id == id })
    }
}
