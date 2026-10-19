import XCTest
@testable import ByteCacheLanguage

final class CodeTokenizerTests: XCTestCase {
    func testSplitsIdentifiersPunctuationAndLiterals() {
        XCTAssertEqual(CodeTokenizer.tokens("let x=foo(1);"), ["let", "x", "=", "foo", "(", "NUM", ")", ";"])
        XCTAssertEqual(CodeTokenizer.tokens("myVar_name"), ["myVar_name"], "identifiers stay whole")
        XCTAssertEqual(CodeTokenizer.tokens(#"print("hi #x", 'y', 3.5e2)"#), ["print", "(", "STR", ",", "STR", ",", "NUM", ")"])
    }

    func testKeepsMultiCharacterOperators() {
        XCTAssertEqual(CodeTokenizer.tokens("a => b :: c -> d := e != f"),
                       ["a", "=>", "b", "::", "c", "->", "d", ":=", "e", "!=", "f"])
    }

    func testIndentationAndLineBreaks() {
        XCTAssertEqual(CodeTokenizer.tokens("if x:\n    y\n\tz"), ["if", "x", ":", "NL", "INDENT", "y", "NL", "TAB", "z"])
    }

    func testCommentMarkersKeptButLongCommentsTruncated() {
        let words = (1...30).map { "w\($0)" }.joined(separator: " ")
        let tokens = CodeTokenizer.tokens("x // \(words)")
        XCTAssertEqual(tokens.prefix(2), ["x", "//"])
        XCTAssertEqual(tokens.count, 2 + 20)
        XCTAssertEqual(CodeTokenizer.tokens("# note\n-- sql"), ["#", "note", "NL", "--", "sql"])
    }

    func testFeaturesAreWordSafeAndDeterministic() {
        let features = CodeTokenizer.features("let x=foo(1);")
        XCTAssertFalse(features.contains("("))
        XCTAssertTrue(features.split(separator: " ").allSatisfy { $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } }, features)
        XCTAssertEqual(features, CodeTokenizer.features("let x=foo(1);"))
        XCTAssertNotEqual(CodeTokenizer.features("a;"), CodeTokenizer.features("a:"))
    }

    func testTruncatesToMaxLines() {
        let code = Array(repeating: "x", count: 10).joined(separator: "\n")
        XCTAssertEqual(CodeTokenizer.tokens(code, maxLines: 3), ["x", "NL", "x", "NL", "x"])
    }

    func testFiveThousandLinesIsFast() {
        let code = Array(repeating: "for (int i = 0; i < n; i++) { total += values[i] * 2; } // sum", count: 5_000)
            .joined(separator: "\n")
        let start = Date()
        _ = CodeTokenizer.features(code)
        // GitHub's virtual Macs are several times slower than a real one.
        let slack = ProcessInfo.processInfo.environment["CI"] == "true" ? 4.0 : 1.0
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.02 * slack)
    }

    func testPairFeaturesGeneraliseLongIdentifiers() {
        let words = CodeTokenizer.features("fooBarBazQux = 1").split(separator: " ").map(String.init)
        XCTAssertTrue(words.contains("fooBarBazQux"), "unigrams keep the identifier")
        XCTAssertTrue(words.contains("IDZZp3d"), "pairs use ID for long identifiers")
        XCTAssertFalse(words.contains("fooBarBazQuxZZp3d"))
        XCTAssertTrue(CodeTokenizer.features("def x").split(separator: " ").contains("defZZx"), "short words stay in pairs")
    }
}
