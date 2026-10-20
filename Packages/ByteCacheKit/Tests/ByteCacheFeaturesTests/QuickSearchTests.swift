import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// CP-48: Quick Search keyboard highlight and copy.
@MainActor
final class QuickSearchTests: XCTestCase {
    func testHighlightStaysInsideTheResults() async {
        let page = TestJSON.page([TestJSON.snippet(1, title: "One"), TestJSON.snippet(2, title: "Two"),
                                  TestJSON.snippet(3, title: "Three")])
        let (session, _) = await TestSession.signedIn([.json(page)])
        let model = QuickSearchModel(list: SnippetListModel(session: session, cache: nil))
        await model.opened()
        XCTAssertEqual(model.highlightedSnippet?.id, model.results.first?.id)
        model.move(by: 1)
        model.move(by: 5)
        XCTAssertEqual(model.highlighted, 2)
        model.move(by: -10)
        XCTAssertEqual(model.highlighted, 0)
    }

    func testEmptyResultsHaveNoHighlight() async {
        let (session, _) = await TestSession.signedIn([.json(TestJSON.page([]))])
        let model = QuickSearchModel(list: SnippetListModel(session: session, cache: nil))
        await model.opened()
        model.move(by: 1)
        XCTAssertNil(model.highlightedSnippet)
    }

    func testCopiesEveryFileInOrder() throws {
        let snippet = Snippet(id: 1, title: "t", description: "", updatedAt: nil, expiryDate: nil, isPublic: false,
                              isPinned: false, isFavorite: false, categories: [],
                              fragments: [Fragment(id: 2, fileName: "b", code: "second", language: "bash", position: 1),
                                          Fragment(id: 1, fileName: "a", code: "first", language: "bash", position: 0)],
                              shareCount: 0)
        XCTAssertEqual(QuickSearchModel.code(of: snippet), "first\n\nsecond")
    }
}
