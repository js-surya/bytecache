import XCTest
import ByteCatchCore
import ByteCatchLanguage
import ByteCatchTestSupport
@testable import ByteCatchFeatures

struct FixedClassifier: LanguageClassifier {
    var ranking: [LanguageGuess]
    func rank(_ text: String) -> [LanguageGuess] { ranking }
}

@MainActor
final class SnippetEditorModelTests: XCTestCase {
    private let swiftDetector = LanguageDetector(classifier: FixedClassifier(ranking: [
        LanguageGuess(id: "swift", confidence: 0.9), LanguageGuess(id: "kotlin", confidence: 0.06),
        LanguageGuess(id: "go", confidence: 0.04),
    ]))

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func existing(isPublic: Bool) throws -> Snippet {
        let json = #"{"id":5,"title":"Two","description":"d","is_public":\#(isPublic ? 1 : 0),"is_pinned":0,"is_favorite":0,"categories":["web"],"fragments":[{"id":1,"file_name":"a.js","code":"a()","language":"javascript","position":0},{"id":2,"file_name":"b.css","code":"b{}","language":"css","position":1}]}"#
        return try JSONDecoder.byteStash.decode(Snippet.self, from: Data(json.utf8))
    }

    func testEditingPublicSnippetKeepsEverythingOnSave() async throws {
        let snippet = try existing(isPublic: true)
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.snippet(5, isPublic: true))])
        let model = SnippetEditorModel(existing: snippet, session: session, detector: swiftDetector)
        model.draft.title = "Renamed"
        _ = try await model.save()

        XCTAssertEqual(transport.last.httpMethod, "PUT")
        XCTAssertEqual(transport.last.url?.path, "/api/snippets/5")
        let sent = try body(transport.last)
        XCTAssertEqual(sent["is_public"] as? Int, 1)
        XCTAssertEqual((sent["fragments"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(sent["categories"] as? [String], ["web"])
        XCTAssertEqual(sent["title"] as? String, "Renamed")
    }

    func testDetectionFollowsCodeUntilUserPicksLanguage() async {
        let (session, _) = await TestSession.signedIn([])
        let model = SnippetEditorModel(existing: nil, session: session, detector: swiftDetector)
        model.draft.fragments[0].code = "let x = 1"
        model.codeChanged(fragment: 0)
        XCTAssertEqual(model.draft.fragments[0].language, "swift")
        XCTAssertEqual(model.suggestions[0]?.map(\.id), ["swift", "kotlin", "go"])

        model.setLanguage("kotlin", fragment: 0)
        model.draft.fragments[0].code = "let y = 2"
        model.codeChanged(fragment: 0)
        XCTAssertEqual(model.draft.fragments[0].language, "kotlin", "manual choice sticks")
    }

    func testExistingFragmentsKeepTheirLanguage() async throws {
        let (session, _) = await TestSession.signedIn([])
        let model = SnippetEditorModel(existing: try existing(isPublic: false), session: session, detector: swiftDetector)
        model.codeChanged(fragment: 0)
        XCTAssertEqual(model.draft.fragments[0].language, "javascript")
    }

    func testNewSnippetTitleFallbacks() async throws {
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.snippet(9), status: 201)])
        let model = SnippetEditorModel(existing: nil, session: session, detector: swiftDetector)
        model.draft.fragments[0].code = "print(1)"
        _ = try await model.save()
        XCTAssertEqual(transport.last.httpMethod, "POST")
        XCTAssertEqual(try body(transport.last)["title"] as? String, "Untitled snippet")

        let (session2, transport2) = await TestSession.signedIn([.json(TestJSON.snippet(9), status: 201)])
        let named = SnippetEditorModel(existing: nil, session: session2, detector: swiftDetector)
        named.draft.fragments[0].code = "print(1)"
        named.draft.fragments[0].fileName = "hello.py"
        _ = try await named.save()
        XCTAssertEqual(try body(transport2.last)["title"] as? String, "hello.py")
    }

    func testCannotSaveWhenAllFragmentsEmpty() async {
        let (session, _) = await TestSession.signedIn([])
        let model = SnippetEditorModel(existing: nil, session: session, detector: swiftDetector)
        XCTAssertFalse(model.canSave)
        model.addFragment()
        model.draft.fragments[1].code = "  \n "
        XCTAssertFalse(model.canSave)
        model.draft.fragments[1].code = "x"
        XCTAssertTrue(model.canSave)
    }

    func testOfflineSaveKeepsDraftAndShowsMessage() async {
        let (session, _) = await TestSession.signedIn([.failure(URLError(.notConnectedToInternet))])
        let model = SnippetEditorModel(existing: nil, session: session, detector: swiftDetector)
        model.draft.fragments[0].code = "keep me"
        do {
            _ = try await model.save()
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .offline)
        }
        XCTAssertEqual(model.draft.fragments[0].code, "keep me")
        XCTAssertEqual(model.error, "You're offline. Check your connection and try again.")
        XCTAssertFalse(model.isSaving)
    }

    func testCategoriesAreNormalised() async throws {
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.snippet(9), status: 201)])
        let model = SnippetEditorModel(existing: nil, session: session, detector: swiftDetector)
        model.draft.fragments[0].code = "x"
        model.draft.categories = [" Web ", "web", "API", ""]
        _ = try await model.save()
        XCTAssertEqual(try body(transport.last)["categories"] as? [String], ["web", "api"])
    }

    func testFragmentListEditing() async {
        let (session, _) = await TestSession.signedIn([])
        let model = SnippetEditorModel(existing: nil, session: session, detector: swiftDetector)
        model.draft.fragments[0].fileName = "a"
        model.addFragment(); model.draft.fragments[1].fileName = "b"
        model.addFragment(); model.draft.fragments[2].fileName = "c"
        model.moveFragment(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(model.draft.fragments.map(\.fileName), ["c", "a", "b"])
        model.removeFragment(at: IndexSet(integer: 0))
        XCTAssertEqual(model.draft.fragments.map(\.fileName), ["a", "b"])
        model.removeFragment(at: IndexSet([0, 1]))
        XCTAssertEqual(model.draft.fragments.count, 1, "always keeps one fragment")
    }

    func testUnauthorizedSaveSignsOut() async throws {
        let (session, _) = await TestSession.signedIn([.json("{}", status: 401), .json(#"{"authRequired":true}"#)])
        let model = SnippetEditorModel(existing: nil, session: session, detector: swiftDetector)
        model.draft.fragments[0].code = "x"
        _ = try? await model.save()
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
    }
}
