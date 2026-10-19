import XCTest
import ByteCatchCore
import ByteCatchLanguage
import ByteCatchTestSupport
@testable import ByteCatchFeatures

struct StubSuggester: SnippetSuggester {
    var result: Result<SnippetSuggestion, Error>
    func suggest(code: String, language: String, knownCategories: [String]) async throws -> SnippetSuggestion {
        try result.get()
    }
}

@MainActor
final class SuggestionTests: XCTestCase {
    private let detector = LanguageDetector.rulesOnly
    private let good = SnippetSuggestion(title: "Fetch JSON with curl", description: "Downloads JSON from an API.",
                                         categories: ["Networking", "shell", "networking", "http", "extra"])

    func testCaptureFillsDefaultsAndNormalisesCategories() async {
        let model = CaptureModel(text: "curl -s https://x.io | jq .", client: nil, detector: detector,
                                 suggester: StubSuggester(result: .success(good)))
        XCTAssertTrue(model.canSuggest)
        await model.suggest()
        XCTAssertEqual(model.title, "Fetch JSON with curl")
        XCTAssertEqual(model.snippetDescription, "Downloads JSON from an API.")
        XCTAssertEqual(model.categories, ["networking", "shell", "http"])
    }

    func testCaptureKeepsWhatTheUserTyped() async {
        let model = CaptureModel(text: "x", client: nil, detector: detector, suggester: StubSuggester(result: .success(good)))
        model.title = "My own title"
        model.categories = ["mine"]
        await model.suggest()
        XCTAssertEqual(model.title, "My own title")
        XCTAssertEqual(model.categories, ["mine"])
        XCTAssertEqual(model.snippetDescription, "Downloads JSON from an API.")
    }

    func testFailureChangesNothing() async {
        struct Boom: Error {}
        let model = CaptureModel(text: "x", client: nil, detector: detector, suggester: StubSuggester(result: .failure(Boom())))
        let before = model.title
        await model.suggest()
        XCTAssertEqual(model.title, before)
        XCTAssertFalse(model.isSuggesting)
    }

    func testNoSuggesterMeansNoButton() {
        XCTAssertFalse(CaptureModel(text: "x", client: nil, detector: detector).canSuggest)
    }

    func testSuggestedDescriptionIsSaved() async throws {
        let transport = StubTransport([.json(TestJSON.snippet(1), status: 201)])
        let client = APIClient(server: TestSession.server, token: "t", transport: transport)
        let model = CaptureModel(text: "x", sourceURL: URL(string: "https://site.io/a"), client: client, detector: detector,
                                 suggester: StubSuggester(result: .success(good)))
        await model.suggest()
        _ = try await model.save()
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(transport.last.httpBody)) as? [String: Any])
        XCTAssertEqual(body["description"] as? String, "Downloads JSON from an API.\n\nSaved from https://site.io/a")
    }

    func testEditorFillsOnlyEmptyFields() async {
        let (session, _) = await TestSession.signedIn([])
        let model = SnippetEditorModel(existing: nil, session: session, detector: detector,
                                       suggester: StubSuggester(result: .success(good)))
        model.draft.fragments[0].code = "curl x"
        model.draft.description = "Keep me"
        await model.suggest()
        XCTAssertEqual(model.draft.title, "Fetch JSON with curl")
        XCTAssertEqual(model.draft.description, "Keep me")
        XCTAssertEqual(model.draft.categories, ["networking", "shell", "http"])
    }
}
