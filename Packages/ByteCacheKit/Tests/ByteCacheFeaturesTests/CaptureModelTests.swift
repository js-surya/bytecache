import XCTest
import ByteCacheCore
import ByteCacheLanguage
import ByteCacheTestSupport
@testable import ByteCacheFeatures

@MainActor
final class CaptureModelTests: XCTestCase {
    private let detector = LanguageDetector(classifier: FixedClassifier(ranking: [
        LanguageGuess(id: "python", confidence: 0.8), LanguageGuess(id: "ruby", confidence: 0.1),
        LanguageGuess(id: "perl", confidence: 0.05),
    ]))
    private let unsure = LanguageDetector(classifier: FixedClassifier(ranking: [
        LanguageGuess(id: "c", confidence: 0.4), LanguageGuess(id: "cpp", confidence: 0.35),
        LanguageGuess(id: "java", confidence: 0.1),
    ]))

    private func client(_ replies: [StubTransport.Reply]) -> (APIClient, StubTransport) {
        let transport = StubTransport(replies)
        return (APIClient(server: TestSession.server, token: "t", transport: transport), transport)
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    /// CP-93: a cloud provider only gets code when the person taps Suggest.
    func testOnlyOnDeviceSuggestersRunOnOpen() {
        struct OnDevice: SnippetSuggester {
            func suggest(code: String, language: String, knownCategories: [String]) async throws -> SnippetSuggestion {
                SnippetSuggestion(title: "", description: "", categories: [])
            }
        }
        let remote = RemoteSuggester(client: RemoteAIClient(provider: .openAI, model: "m", keys: MemoryAIKeyStore()))
        XCTAssertTrue(CaptureModel(text: "x", client: nil, detector: detector, suggester: OnDevice()).suggestsOnOpen)
        let cloud = CaptureModel(text: "x", client: nil, detector: detector, suggester: remote)
        XCTAssertTrue(cloud.canSuggest)
        XCTAssertFalse(cloud.suggestsOnOpen)
        XCTAssertFalse(CaptureModel(text: "x", client: nil, detector: detector).suggestsOnOpen)
    }

    func testPreselectsDetectedLanguageWithCandidates() {
        let model = CaptureModel(text: "print('hi')", client: nil, detector: detector)
        XCTAssertEqual(model.language, "python")
        XCTAssertEqual(model.candidates.map(\.id), ["python", "ruby", "perl"])
    }

    func testAbstainsToPlaintextButShowsCandidates() {
        let model = CaptureModel(text: "int x;", client: nil, detector: unsure)
        XCTAssertEqual(model.language, "plaintext")
        XCTAssertEqual(model.candidates.map(\.id), ["c", "cpp", "java"])
    }

    func testTitleDefaults() {
        XCTAssertEqual(CaptureModel(text: "\n\n  import os  \nx", client: nil, detector: detector).title, "import os")
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(CaptureModel(text: long, client: nil, detector: detector).title.count, 60)
        XCTAssertEqual(CaptureModel(text: "x", fileName: "run.sh", client: nil, detector: detector).title, "run.sh")
        XCTAssertEqual(CaptureModel(text: "x", pageTitle: "How to curl", client: nil, detector: detector).title, "How to curl")
    }

    func testWhitespaceOnlyCannotSave() {
        let (api, _) = client([])
        XCTAssertFalse(CaptureModel(text: " \n\t ", client: api, detector: detector).canSave)
        XCTAssertTrue(CaptureModel(text: "x", client: api, detector: detector).canSave)
    }

    func testSignedOutCannotSave() async {
        let model = CaptureModel(text: "x", client: nil, detector: detector)
        XCTAssertTrue(model.signedOut)
        XCTAssertFalse(model.canSave)
        do {
            _ = try await model.save()
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testSavePostsSingleFragmentWithNormalisedLineEndings() async throws {
        let (api, transport) = client([.json(TestJSON.snippet(3), status: 201)])
        let model = CaptureModel(text: "a\r\nb", fileName: "x.py", client: api, detector: detector)
        model.categories = ["Tools"]
        _ = try await model.save()
        let sent = try body(transport.last)
        let fragments = try XCTUnwrap(sent["fragments"] as? [[String: Any]])
        XCTAssertEqual(fragments.count, 1)
        XCTAssertEqual(fragments[0]["code"] as? String, "a\nb")
        XCTAssertEqual(fragments[0]["file_name"] as? String, "x.py")
        XCTAssertEqual(fragments[0]["language"] as? String, "python")
        XCTAssertEqual(sent["categories"] as? [String], ["tools"])
        XCTAssertEqual(sent["is_public"] as? Int, 0)
    }

    func testDefaultFileName() async throws {
        let (api, transport) = client([.json(TestJSON.snippet(3), status: 201)])
        _ = try await CaptureModel(text: "x", client: api, detector: detector).save()
        let fragments = try XCTUnwrap(try body(transport.last)["fragments"] as? [[String: Any]])
        XCTAssertEqual(fragments[0]["file_name"] as? String, "snippet")
    }

    func testUnauthorizedCallsHandlerAndKeepsText() async {
        let (api, _) = client([.json("{}", status: 401)])
        var signedOut = false
        let model = CaptureModel(text: "keep", client: api, detector: detector, onUnauthorized: { signedOut = true })
        _ = try? await model.save()
        XCTAssertTrue(signedOut)
        XCTAssertEqual(model.text, "keep")
        XCTAssertEqual(model.error, CaptureModel.signInMessage)
    }

    func testTextChangeRedetectsUntilLanguagePicked() {
        let model = CaptureModel(text: "", client: nil, detector: detector)
        XCTAssertEqual(model.language, "plaintext")
        model.text = "print(1)"
        model.textChanged()
        XCTAssertEqual(model.language, "python")
        model.pickLanguage("ruby")
        model.text = "print(2)"
        model.textChanged()
        XCTAssertEqual(model.language, "ruby")
    }
}
