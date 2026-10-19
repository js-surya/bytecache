import XCTest
@testable import ByteCatchFeatures

final class CodeEditingTests: XCTestCase {
    /// Applies an edit; "|" in `text` marks the caret.
    private func run(_ text: String, _ edit: (String, NSRange) -> TextEdit?) -> String? {
        let caret = (text as NSString).range(of: "|").location
        let plain = text.replacingOccurrences(of: "|", with: "")
        guard let e = edit(plain, NSRange(location: caret, length: 0)) else { return nil }
        let result = (plain as NSString).replacingCharacters(in: e.range, with: e.replacement) as NSString
        return result.replacingCharacters(in: NSRange(location: e.selection.location, length: 0), with: "|")
    }

    func testNewlineKeepsIndent() {
        XCTAssertEqual(run("    let a = 1|") { CodeEditing.newline(in: $0, selection: $1, indentUnit: "    ") },
                       "    let a = 1\n    |")
    }

    func testNewlineAfterOpenerIndentsMore() {
        XCTAssertEqual(run("if x {|") { CodeEditing.newline(in: $0, selection: $1, indentUnit: "  ") }, "if x {\n  |")
        XCTAssertEqual(run("def f():|") { CodeEditing.newline(in: $0, selection: $1, indentUnit: "    ") }, "def f():\n    |")
    }

    func testNewlineBetweenPairSplitsIt() {
        XCTAssertEqual(run("\tfn() {|}") { CodeEditing.newline(in: $0, selection: $1, indentUnit: "\t") },
                       "\tfn() {\n\t\t|\n\t}")
    }

    func testAutoClosesBracketsAndQuotes() {
        XCTAssertEqual(run("call|") { CodeEditing.insert("(", in: $0, selection: $1) }, "call(|)")
        XCTAssertEqual(run("x = |") { CodeEditing.insert("\"", in: $0, selection: $1) }, "x = \"|\"")
        XCTAssertNil(run("don|") { CodeEditing.insert("'", in: $0, selection: $1) }, "apostrophe after a letter stays single")
        XCTAssertNil(run("|abc") { CodeEditing.insert("(", in: $0, selection: $1) }, "no pair right before a word")
    }

    func testTypingCloserStepsOverExistingOne() {
        XCTAssertEqual(run("call(|)") { CodeEditing.insert(")", in: $0, selection: $1) }, "call()|")
        XCTAssertEqual(run("\"a|\"") { CodeEditing.insert("\"", in: $0, selection: $1) }, "\"a\"|")
        XCTAssertNil(run("call(|") { CodeEditing.insert(")", in: $0, selection: $1) })
    }

    func testWrapsSelection() {
        let e = CodeEditing.insert("[", in: "a b c", selection: NSRange(location: 2, length: 1))
        XCTAssertEqual(e, TextEdit(range: NSRange(location: 2, length: 1), replacement: "[b]", selection: NSRange(location: 3, length: 1)))
    }

    func testBackspaceRemovesEmptyPair() {
        XCTAssertEqual(run("f(|)") { CodeEditing.deleteBackward(in: $0, selection: $1) }, "f|")
        XCTAssertNil(run("f(x|)") { CodeEditing.deleteBackward(in: $0, selection: $1) })
    }

    func testMatchingBracket() {
        let text = "a(b[c]{d})"
        XCTAssertEqual(CodeEditing.matchingBracket(in: text, caret: 2)?.match, 9, "after '(' finds ')'")
        XCTAssertEqual(CodeEditing.matchingBracket(in: text, caret: 10)?.match, 1, "after ')' finds '('")
        XCTAssertEqual(CodeEditing.matchingBracket(in: text, caret: 6)?.match, 3)
        XCTAssertNil(CodeEditing.matchingBracket(in: "a(b", caret: 2))
        XCTAssertNil(CodeEditing.matchingBracket(in: "abc", caret: 1))
    }

    func testIndentUnitDetection() {
        XCTAssertEqual(CodeEditing.indentUnit(for: "a\n\tb"), "\t")
        XCTAssertEqual(CodeEditing.indentUnit(for: "a:\n  b\n    c"), "  ")
        XCTAssertEqual(CodeEditing.indentUnit(for: "plain"), "    ")
    }

    func testLineStarts() {
        XCTAssertEqual(CodeEditing.lineStarts(in: "a\nbc\n"), [0, 2, 5])
        XCTAssertEqual(CodeEditing.lineStarts(in: ""), [0])
    }
}
