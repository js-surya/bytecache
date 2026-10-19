import XCTest
@testable import ByteCacheFeatures

/// CP-31: wrapped code keeps one row per logical line, so line numbers stay aligned.
final class CodeLinesTests: XCTestCase {
    func testPlainLinesKeepEmptyLines() {
        XCTAssertEqual(CodeLines.plain("a\n\nb\n"), ["a", "", "b", ""])
        XCTAssertEqual(CodeLines.plain(""), [""])
    }

    func testHighlightedTextSplitsIntoTheSameLines() {
        var keyword = AttributedString("let")
        keyword.inlinePresentationIntent = .stronglyEmphasized
        let highlighted = keyword + AttributedString(" x = 1\n/* a\n b */")
        let lines = CodeLines.split(highlighted, original: "let x = 1\n/* a\n b */")
        XCTAssertEqual(lines?.map { String($0.characters) }, ["let x = 1", "/* a", " b */"])
        XCTAssertEqual(lines?.first?.runs.first?.inlinePresentationIntent, .stronglyEmphasized)
    }

    func testRestoresWhitespaceTheHighlighterTrims() {
        // HighlightSwift trims leading/trailing whitespace, which would shift every line number.
        let lines = CodeLines.split(AttributedString("x()\n}"), original: "\n\n    x()\n}\n")
        XCTAssertEqual(lines?.map { String($0.characters) }, ["", "", "    x()", "}", ""])
    }

    func testMismatchFallsBackToPlain() {
        XCTAssertNil(CodeLines.split(AttributedString("one line"), original: "two\nlines"))
    }
}
