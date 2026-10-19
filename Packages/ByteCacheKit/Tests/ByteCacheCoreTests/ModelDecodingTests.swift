import XCTest
@testable import ByteCacheCore

private struct Box: Decodable { @FlexibleBool var v: Bool }

final class ModelDecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func sample() -> Snippet {
        Snippet(
            id: 1, title: "t", description: "d", updatedAt: nil, expiryDate: nil,
            isPublic: false, isPinned: false, isFavorite: false, categories: [],
            fragments: [
                Fragment(id: 2, fileName: "b", code: "2", language: "swift", position: 1),
                Fragment(id: 1, fileName: "a", code: "1", language: "swift", position: 0),
            ],
            shareCount: 0
        )
    }

    func testDecodesLivePageWithIntBooleans() throws {
        let page = try JSONDecoder.byteStash.decode(SnippetPage.self, from: fixture("snippet_page"))
        XCTAssertEqual(page.total, 1323)
        XCTAssertTrue(page.hasMore)
        let s = page.snippets[0]
        XCTAssertEqual(s.id, 1796)
        XCTAssertFalse(s.isPinned)
        XCTAssertEqual(s.fragments.map(\.fileName), ["main", "file2"])
        XCTAssertEqual(s.updatedAt, date("2026-10-18T00:45:14Z"))
    }

    func testFlexibleBoolAcceptsIntAndBool() throws {
        func decode(_ json: String) throws -> Bool {
            try JSONDecoder().decode(Box.self, from: Data(json.utf8)).v
        }
        XCTAssertTrue(try decode(#"{"v":1}"#))
        XCTAssertTrue(try decode(#"{"v":true}"#))
        XCTAssertFalse(try decode(#"{"v":0}"#))
    }

    func testDraftFromPublicSnippetKeepsEverything() throws {
        var s = sample()
        s.isPublic = true
        s.categories = ["bash"]
        let data = try JSONEncoder().encode(SnippetDraft(from: s))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["is_public"] as? Int, 1)
        let fragments = try XCTUnwrap(json["fragments"] as? [[String: Any]])
        XCTAssertEqual(fragments.count, s.fragments.count)
        XCTAssertEqual(fragments.map { $0["file_name"] as? String }, ["a", "b"])
        XCTAssertEqual(json["categories"] as? [String], ["bash"])
    }

    func testFragmentIdentityFallsBackToPosition() {
        XCTAssertEqual(Fragment(id: nil, fileName: "x", code: "", language: "", position: 3).id, 3)
    }
}
