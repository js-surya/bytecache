import XCTest
@testable import ByteCacheFeatures
#if canImport(AppKit)
import AppKit
#endif

final class OCRLayoutTests: XCTestCase {
    /// Boxes in top-left coordinates, 0…1; each character is 0.01 wide, each line 0.04 tall.
    private func piece(_ text: String, col: Int, row: Double) -> OCRPiece {
        OCRPiece(text: text, minX: 0.1 + Double(col) * 0.01, minY: 0.1 + row * 0.05,
                 width: Double(text.count) * 0.01, height: 0.04)
    }

    func testRebuildsLinesIndentationAndBlankLines() {
        let pieces = [
            piece("}", col: 0, row: 3),
            piece("def greet(name):", col: 0, row: 0),
            piece("return name", col: 4, row: 1),
            piece("print(1)", col: 0, row: 5),
        ]
        XCTAssertEqual(OCRLayout.reconstruct(pieces), "def greet(name):\n    return name\n\n}\n\nprint(1)")
    }

    func testPiecesOnTheSameRowJoinLeftToRight() {
        let pieces = [piece("+ b", col: 8, row: 0), piece("let x = a", col: 0, row: 0)]
        XCTAssertEqual(OCRLayout.reconstruct(pieces), "let x = a + b")
    }

    func testCyrillicAndGreekLookAlikesBecomeLatinInCode() {
        XCTAssertEqual(OCRLayout.fixLookAlikes("return \u{0430} + 1"), "return a + 1")
        XCTAssertEqual(OCRLayout.fixLookAlikes("\u{0441}\u{043E}nst \u{0445} = \u{03BF}k"), "const x = ok")
        XCTAssertEqual(OCRLayout.fixLookAlikes("привет мир"), "привет мир", "real Cyrillic text is left alone")
    }

    func testEmpty() {
        XCTAssertEqual(OCRLayout.reconstruct([]), "")
    }
}

struct FixedRecognizer: TextRecognizing {
    let result: Result<String, Error>
    func recognize(imageData: Data) async throws -> String { try result.get() }
}

@MainActor
final class ScanCodeModelTests: XCTestCase {
    func testRecognizedTextIsDelivered() async {
        let model = ScanCodeModel(recognizer: FixedRecognizer(result: .success("let x = 1\n")))
        let text = await model.recognize(imageData: Data([1]))
        XCTAssertEqual(text, "let x = 1")
        XCTAssertNil(model.error)
    }

    func testNoTextShowsMessage() async {
        let model = ScanCodeModel(recognizer: FixedRecognizer(result: .success("  \n ")))
        let text = await model.recognize(imageData: Data([1]))
        XCTAssertNil(text)
        XCTAssertEqual(model.error, "No text found in that image. Try a sharper, closer shot.")
    }

    func testUnreadableImage() async {
        struct Bad: Error {}
        let model = ScanCodeModel(recognizer: FixedRecognizer(result: .failure(Bad())))
        _ = await model.recognize(imageData: Data())
        XCTAssertEqual(model.error, "ByteCache couldn't read that image.")
    }

    #if canImport(AppKit)
    func testRealRecognitionOfRenderedCode() async throws {
        // Measures Apple's text recognizer, which differs between macOS versions; CI runs an older one.
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] == "true", "Vision results depend on the macOS version")
        let code = "func add(a: Int) -> Int {\n    return a + 1\n}"
        let image = NSImage(size: NSSize(width: 900, height: 260), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            NSAttributedString(string: code, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 34, weight: .regular),
                                                         .foregroundColor: NSColor.black])
                .draw(at: NSPoint(x: 30, y: 30))
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let text = try await VisionTextRecognizer().recognize(imageData: png)
        let lines = text.split(separator: "\n").map(String.init)
        // Vision doesn't report a lone "}" line; the capture sheet lets the user add it.
        XCTAssertGreaterThanOrEqual(lines.count, 2, text)
        XCTAssertTrue(lines[0].contains("func add"), text)
        XCTAssertTrue(lines[1].hasPrefix("    return a + 1"), "indentation kept, Latin letters: \(text)")
        XCTAssertTrue(text.unicodeScalars.allSatisfy(\.isASCII), text)
    }
    #endif
}
