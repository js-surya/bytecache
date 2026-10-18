import XCTest
@testable import ByteCatchCore

final class ServerURLTests: XCTestCase {
    func testServerURLNormalization() throws {
        let cases = [
            "demo.example.com": "https://demo.example.com",
            "https://demo.example.com/": "https://demo.example.com",
            "  https://demo.example.com  ": "https://demo.example.com",
            "http://nas.local:5000/bytestash/": "http://nas.local:5000/bytestash",
            "https://x.io/bytestash/api": "https://x.io/bytestash",
            "https://x.io/login": "https://x.io",
        ]
        for (raw, want) in cases {
            XCTAssertEqual(try ServerURL(raw).base.absoluteString, want, raw)
        }
    }

    func testEndpointNeverDoublesSlashes() throws {
        XCTAssertEqual(
            try ServerURL("https://x.io/b/").endpoint("/api/snippets").absoluteString,
            "https://x.io/b/api/snippets"
        )
        XCTAssertEqual(
            try ServerURL("https://x.io").endpoint("api/snippets").absoluteString,
            "https://x.io/api/snippets"
        )
    }

    func testRejectsInvalidInput() {
        XCTAssertThrowsError(try ServerURL(""))
        XCTAssertThrowsError(try ServerURL("   "))
        XCTAssertThrowsError(try ServerURL("ftp://x"))
    }

    func testCacheKeyIsStableAcrossLooseInput() throws {
        XCTAssertEqual(try ServerURL("X.io/").cacheKey, try ServerURL("https://x.io").cacheKey)
    }
}
