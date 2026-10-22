import XCTest
@testable import ByteCacheCore

/// Request paths in the activity log: known words stay, anything else (IDs, share links) is hidden.
final class LogPathTests: XCTestCase {
    func testKnownRoutesStayReadable() {
        XCTAssertEqual(APIClient.logPath("/api/snippets"), "/api/snippets")
        XCTAssertEqual(APIClient.logPath("/api/auth/config"), "/api/auth/config")
        XCTAssertEqual(APIClient.logPath("api/snippets/metadata"), "/api/snippets/metadata")
    }

    func testIDsAndShareLinksAreReplaced() {
        XCTAssertEqual(APIClient.logPath("/api/snippets/42/pin"), "/api/snippets/<id>/pin")
        XCTAssertEqual(APIClient.logPath("/api/share/aB3xYzSecret"), "/api/share/<id>")
        XCTAssertEqual(APIClient.logPath("/api/share/recipes"), "/api/share/<id>", "a share ID can look like a word")
        XCTAssertEqual(APIClient.logPath("/api/share/snippet/7"), "/api/share/snippet/<id>")
        XCTAssertEqual(APIClient.logPath("/api/keys/9f2c"), "/api/keys/<id>")
    }

    func testQueriesAreDropped() {
        XCTAssertEqual(APIClient.logPath("/api/public/snippets?search=my secret"), "/api/public/snippets")
    }
}
