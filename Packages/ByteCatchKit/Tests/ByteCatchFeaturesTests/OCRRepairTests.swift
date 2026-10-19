import XCTest
@testable import ByteCatchFeatures

/// CP-15: fixes for what Vision gets wrong in code.
final class OCRRepairTests: XCTestCase {
    func testTypographicSymbolsBecomeASCII() {
        XCTAssertEqual(OCRLayout.normalizeSymbols("def f() → int: x ⇒ y ≠ z ≤ 1 ≥ 2 “a” ‘b’ …"),
                       "def f() -> int: x => y != z <= 1 >= 2 \"a\" 'b' ...")
    }

    func testMismatchedBracketPairsTrustTheCurlyOne() {
        XCTAssertEqual(OCRLayout.repairBrackets("return (\"lines\": data, \"count\": len(data)}"),
                       "return {\"lines\": data, \"count\": len(data)}")
        XCTAssertEqual(OCRLayout.repairBrackets("items = (1, 2]"), "items = [1, 2]")
        XCTAssertEqual(OCRLayout.repairBrackets("f(a[0], {b})"), "f(a[0], {b})", "balanced lines are untouched")
        XCTAssertEqual(OCRLayout.repairBrackets("if (x) {"), "if (x) {", "open block is fine")
    }

    func testIndentsOffByOneSnapToTheStep() {
        let lines = ["def f():", "   if x:", "        return 1", "    return 2"]
        XCTAssertEqual(OCRLayout.snapIndents(lines), ["def f():", "    if x:", "        return 1", "    return 2"])
        XCTAssertEqual(OCRLayout.snapIndents(["a", "  b", "   c", "    d"]), ["a", "  b", "  c", "    d"], "two-space code")
    }

    func testDeskewStraightensAnAngledPhoto() {
        // Three lines of text tilted by 6°, each 400 px wide, 40 px apart.
        let angle = 6.0 * .pi / 180
        func line(_ text: String, x: Double, y: Double) -> OCRLine {
            let dx = cos(angle) * 400, dy = sin(angle) * 400
            return OCRLine(text: text, topLeft: CGPoint(x: x, y: y), topRight: CGPoint(x: x + dx, y: y + dy),
                           bottomLeft: CGPoint(x: x, y: y + 30), bottomRight: CGPoint(x: x + dx, y: y + dy + 30))
        }
        let lines = [line("first();", x: 100, y: 100), line("second();", x: 96, y: 140), line("third();", x: 92, y: 180)]
        let pieces = OCRLayout.pieces(from: lines, imageSize: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(OCRLayout.reconstruct(pieces), "first();\nsecond();\nthird();")
    }
}
