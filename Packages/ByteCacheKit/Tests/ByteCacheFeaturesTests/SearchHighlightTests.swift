import XCTest
@testable import ByteCacheFeatures

/// CP-30: search matches are highlighted in result rows.
final class SearchHighlightTests: XCTestCase {
    private func marked(_ text: AttributedString) -> [String] {
        text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(text[$0.range].characters) }
    }

    func testMarksEveryMatchIgnoringCase() {
        XCTAssertEqual(marked(SearchHighlight.mark("Parse CSV, then parse JSON", query: "parse")), ["Parse", "parse"])
    }

    func testMatchesTheWholePhrase() {
        XCTAssertEqual(marked(SearchHighlight.mark("read csv file", query: " csv file ")), ["csv file"])
        XCTAssertEqual(marked(SearchHighlight.mark("read csv", query: "csv file")), [])
    }

    func testEmptyQueryMarksNothing() {
        XCTAssertEqual(marked(SearchHighlight.mark("anything", query: "  ")), [])
    }

    func testMatchingLineFindsTheLineAndKeepsTheMatchVisible() {
        let code = "import csv\n    reader = csv.DictReader(file)\n"
        XCTAssertEqual(SearchHighlight.matchingLine(in: code, query: "dictreader"), "reader = csv.DictReader(file)")
        let long = String(repeating: "x", count: 40) + " needle"
        XCTAssertEqual(SearchHighlight.matchingLine(in: long, query: "needle", lead: 4), "…xxx needle")
        XCTAssertNil(SearchHighlight.matchingLine(in: code, query: "missing"))
    }
}
