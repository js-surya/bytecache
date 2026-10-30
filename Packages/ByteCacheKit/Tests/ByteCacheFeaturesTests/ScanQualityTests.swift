import XCTest
import CoreImage
@testable import ByteCacheFeatures
import ByteCacheLanguage

/// Straightening photographed pages before reading them.
final class PageStraighteningTests: XCTestCase {
    private func quad(_ inset: CGFloat, in size: CGSize) -> PageStraightening.Quad {
        PageStraightening.Quad(topLeft: CGPoint(x: inset, y: size.height - inset),
                               topRight: CGPoint(x: size.width - inset, y: size.height - inset),
                               bottomLeft: CGPoint(x: inset, y: inset),
                               bottomRight: CGPoint(x: size.width - inset, y: inset))
    }

    func testOnlyAConfidentPageThatIsPartOfThePhoto() {
        let size = CGSize(width: 1000, height: 1000)
        XCTAssertTrue(PageStraightening.worthStraightening(quad(150, in: size), confidence: 0.95, imageSize: size))
        XCTAssertFalse(PageStraightening.worthStraightening(quad(150, in: size), confidence: 0.5, imageSize: size), "unsure")
        XCTAssertFalse(PageStraightening.worthStraightening(quad(5, in: size), confidence: 0.95, imageSize: size), "already the whole image")
        XCTAssertFalse(PageStraightening.worthStraightening(quad(400, in: size), confidence: 0.95, imageSize: size), "a small patch, not the page")
    }

    #if os(macOS)
    /// A page of code photographed at an angle on a dark desk: it's found, flattened and read.
    func testPhotographedPageAtAnAngleIsRead() async throws {
        let page = CIImage(data: OCREvalTests.render(OCREvalTests.sample, .init(name: "page", fontSize: 30)))!
        let w = page.extent.width, h = page.extent.height
        let canvas = CGRect(x: 0, y: 0, width: w * 1.6, height: h * 1.8)
        let tilted = page.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: w * 0.30, y: h * 1.55),
            "inputTopRight": CIVector(x: w * 1.40, y: h * 1.45),
            "inputBottomLeft": CIVector(x: w * 0.15, y: h * 0.25),
            "inputBottomRight": CIVector(x: w * 1.50, y: h * 0.35),
        ])
        let photo = tilted.composited(over: CIImage(color: CIColor(red: 0.2, green: 0.17, blue: 0.14)).cropped(to: canvas))
        let cgPhoto = CIContext().createCGImage(photo, from: canvas)!
        XCTAssertNotNil(PageStraightening.straightened(cgPhoto), "the page is found")

        let data = NSBitmapImageRep(cgImage: cgPhoto).representation(using: .png, properties: [:])!
        let text = try await OCREvalTests.patient.recognize(imageData: data)
        let accuracy = OCREvalTests.accuracy(text, OCREvalTests.sample)
        XCTAssertGreaterThan(accuracy, 0.9, text)
        XCTAssertTrue(text.contains("\n        return {}"), "indentation survives: \n\(text)")
    }
    #endif
}

final class ScanFixTests: XCTestCase {
    func testAnswerLosesFencesAndMustStayClose() {
        let original = "if x == 1:\n    print(\"one\")"
        XCTAssertEqual(ScanFix.cleaned("```python\nif x == 1:\n    print(\"one\")\n```", original: original),
                       "if x == 1:\n    print(\"one\")")
        XCTAssertEqual(ScanFix.cleaned("if x == 1:\n    print(\"one\")  \n", original: original), "if x == 1:\n    print(\"one\")")
        XCTAssertNil(ScanFix.cleaned("", original: original))
        XCTAssertNil(ScanFix.cleaned("Here is a long explanation of what this code does and how it could be better written…" + String(repeating: " more", count: 20),
                                     original: original), "far longer: not a correction")
    }

    func testPictureGoesWithEachProvidersFormat() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x01])
        let base64 = jpeg.base64EncodedString()

        let openAI = RecordingTransport(body: #"{"choices":[{"message":{"content":"print(1)"}}]}"#)
        let fixed = try await RemoteScanFixer(client: RemoteAIClient(provider: .openAI, model: "gpt-5", keys: MemoryAIKeyStore([.openAI: "k"]), transport: openAI))
            .fix(code: "prlnt(1)", jpeg: jpeg)
        XCTAssertEqual(fixed, "print(1)")
        let openAIContent = ((json(openAI.requests.first)["messages"] as? [[String: Any]])?[1]["content"] as? [[String: Any]]) ?? []
        XCTAssertEqual((openAIContent.last?["image_url"] as? [String: String])?["url"], "data:image/jpeg;base64,\(base64)")

        let anthropic = RecordingTransport(body: #"{"content":[{"type":"text","text":"print(1)"}]}"#)
        _ = try await RemoteScanFixer(client: RemoteAIClient(provider: .anthropic, model: "m", keys: MemoryAIKeyStore([.anthropic: "k"]), transport: anthropic))
            .fix(code: "prlnt(1)", jpeg: jpeg)
        let anthropicContent = ((json(anthropic.requests.first)["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        XCTAssertEqual((anthropicContent.first?["source"] as? [String: String])?["data"], base64)

        let gemini = RecordingTransport(body: #"{"candidates":[{"content":{"parts":[{"text":"print(1)"}]}}]}"#)
        _ = try await RemoteScanFixer(client: RemoteAIClient(provider: .gemini, model: "gemini-2.5-flash", keys: MemoryAIKeyStore([.gemini: "k"]), transport: gemini))
            .fix(code: "prlnt(1)", jpeg: jpeg)
        let parts = (((json(gemini.requests.first)["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]]) ?? []
        XCTAssertEqual((parts.first?["inline_data"] as? [String: String])?["data"], base64)
    }

    func testPlainRequestsStayTextOnly() async throws {
        let transport = RecordingTransport(body: #"{"choices":[{"message":{"content":"ok"}}]}"#)
        _ = try await RemoteAIClient(provider: .openAI, model: "m", keys: MemoryAIKeyStore([.openAI: "k"]), transport: transport)
            .complete(system: "S", prompt: "P")
        let messages = json(transport.requests.first)["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?[1]["content"] as? String, "P")
    }

    private func json(_ request: URLRequest?) -> [String: Any] {
        (request?.httpBody).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }
}

@MainActor
final class FixScanModelTests: XCTestCase {
    struct StubFixer: ScanFixer {
        var result: Result<String, Error>
        func fix(code: String, jpeg: Data) async throws -> String { try result.get() }
    }

    private func model(_ fixer: StubFixer?) -> CaptureModel {
        let model = CaptureModel(text: "prlnt(1)", client: nil,
                                 detector: LanguageDetector(classifier: FixedClassifier(ranking: [LanguageGuess(id: "python", confidence: 0.9)])))
        model.readFromImage = true
        model.scanImage = Data([1, 2, 3])
        model.scanFixer = fixer
        return model
    }

    func testFixReplacesTextAndCanBeUndone() async {
        let capture = model(StubFixer(result: .success("print(1)")))
        XCTAssertTrue(capture.canFixScan)
        await capture.fixScan()
        XCTAssertEqual(capture.text, "print(1)")
        XCTAssertFalse(capture.canFixScan, "once is enough")
        capture.undoFix()
        XCTAssertEqual(capture.text, "prlnt(1)")
        XCTAssertNil(capture.textBeforeFix)
    }

    func testFailureKeepsTheScanAndSaysWhy() async {
        let capture = model(StubFixer(result: .failure(ScanFix.TooDifferent())))
        await capture.fixScan()
        XCTAssertEqual(capture.text, "prlnt(1)")
        XCTAssertEqual(capture.fixError, ScanFix.TooDifferent().errorDescription)
    }

    func testNoFixWithoutAPictureOrProvider() {
        XCTAssertFalse(model(nil).canFixScan)
        let typed = model(StubFixer(result: .success("x")))
        typed.readFromImage = false
        XCTAssertFalse(typed.canFixScan)
    }
}
