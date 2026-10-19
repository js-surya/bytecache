import XCTest
@testable import ByteCatchFeatures

@MainActor
final class EditorHighlighterTests: XCTestCase {
    func testColorsKeywordsDifferentlyAndKeepsOffsets() async throws {
        let code = "func greet() {\n    let name = \"hi\" // é😀\n    return\n}\n"
        let palette = CodeTheme.named("github")!.palette(for: .light)
        let found = await EditorHighlighter().runs(for: code, language: "swift", palette: palette)
        let runs = try XCTUnwrap(found)
        let ns = code as NSString
        let keyword = runs.first { ns.substring(with: $0.range) == "func" }
        let string = runs.first { ns.substring(with: $0.range).contains("\"hi\"") }
        XCTAssertNotNil(keyword)
        XCTAssertNotNil(string)
        XCTAssertNotEqual(keyword?.hex, string?.hex)
        XCTAssertTrue(runs.allSatisfy { NSMaxRange($0.range) <= ns.length })
        XCTAssertTrue(runs.contains { ns.substring(with: $0.range).contains("return") }, "offsets survive emoji")
    }

    func testPlaintextAndHugeTextAreSkipped() async {
        let palette = CodeTheme.named("github")!.palette(for: .light)
        let none = await EditorHighlighter().runs(for: "hello", language: "plaintext", palette: palette)
        XCTAssertEqual(none?.count ?? 0, 0)
        let huge = await EditorHighlighter().runs(for: String(repeating: "a", count: EditorHighlighter.maxLength + 1),
                                                  language: "swift", palette: palette)
        XCTAssertNil(huge)
    }
}
