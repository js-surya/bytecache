import XCTest
@testable import ByteCacheFeatures

/// CP-86: in Select mode on the Mac every click adds or removes that snippet.
final class SelectModeTests: XCTestCase {
    func testClickAddsASnippet() {
        XCTAssertEqual(SelectModeSelection.toggling(2, in: [1]), [1, 2])
        XCTAssertEqual(SelectModeSelection.toggling(3, in: []), [3])
    }

    func testClickOnASelectedSnippetRemovesIt() {
        XCTAssertEqual(SelectModeSelection.toggling(1, in: [1, 2]), [2])
        XCTAssertEqual(SelectModeSelection.toggling(1, in: [1]), [], "the only selected snippet can be unselected too")
    }
}
