import XCTest
import ByteCacheCore
@testable import ByteCacheFeatures

/// CP-53: Share as Image.
@MainActor
final class CodeImageTests: XCTestCase {
    private let palette = CodeTheme.named(CodeTheme.defaultID)!.palette(for: .light)

    func testLongFilesAreCutAndHighlighted() async {
        let code = (1...75).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        let result = await CodeImage.lines(of: Fragment(id: 1, fileName: "a.swift", code: code, language: "swift", position: 0),
                                           palette: palette)
        XCTAssertEqual(result.lines.count, CodeImage.maxLines)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(String(result.lines[0].characters), "let value1 = 1")
    }

    func testRendersAnImage() async throws {
        let fragment = Fragment(id: 1, fileName: "hello.py", code: "print(\"hi\")", language: "python", position: 0)
        let result = await CodeImage.lines(of: fragment, palette: palette)
        XCTAssertFalse(result.truncated)
        let image = try XCTUnwrap(CodeImage.render(CodeCardView(
            fileName: "hello.py", lines: result.lines, truncated: false, palette: palette, fontSize: 14,
            showLineNumbers: true, background: .accent, accent: .blue
        ), scale: 1))
        XCTAssertGreaterThan(image.size.width, 100)
        XCTAssertGreaterThan(image.size.height, 60)
    }
}
