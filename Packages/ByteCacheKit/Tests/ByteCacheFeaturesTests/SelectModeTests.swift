import XCTest
@testable import ByteCacheFeatures

/// CP-86: in Select mode on the Mac, a plain click adds or removes a snippet instead of replacing
/// the selection; ⌘- and ⇧-clicks and the arrow keys keep their usual meaning.
final class SelectModeTests: XCTestCase {
    private func pick(_ old: Set<Int>, _ new: Set<Int>, plainClick: Bool = true) -> Set<Int> {
        SelectModeSelection.apply(old: old, new: new, plainClick: plainClick)
    }

    func testPlainClickAddsASnippet() {
        XCTAssertEqual(pick([1], [2]), [1, 2])
        XCTAssertEqual(pick([], [3]), [3])
    }

    func testPlainClickOnASelectedSnippetRemovesIt() {
        XCTAssertEqual(pick([1, 2], [1]), [2])
        XCTAssertEqual(pick([1], [1]), [])
    }

    func testModifierClicksAndKeysAreKeptAsTheListMadeThem() {
        XCTAssertEqual(pick([1, 2], [1], plainClick: false), [1]) // ⌘-click removed 2
        XCTAssertEqual(pick([1], [1, 2, 3], plainClick: false), [1, 2, 3]) // ⇧-click range
        XCTAssertEqual(pick([1], [2], plainClick: false), [2]) // arrow key
    }

    func testAnythingButOneRowIsKept() {
        XCTAssertEqual(pick([1], [1, 2]), [1, 2]) // "Select All" and similar
        XCTAssertEqual(pick([1, 2], []), [])
    }
}
