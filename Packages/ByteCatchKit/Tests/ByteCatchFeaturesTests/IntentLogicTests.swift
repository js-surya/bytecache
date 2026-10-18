import XCTest
import ByteCatchCore
import ByteCatchLanguage
import ByteCatchTestSupport
@testable import ByteCatchFeatures

@MainActor
final class IntentLogicTests: XCTestCase {
    private let detector = LanguageDetector(classifier: FixedClassifier(ranking: [LanguageGuess(id: "python", confidence: 0.9)]))
    private let server = TestSession.server

    private func signedInStore() -> InMemoryCredentialStore {
        InMemoryCredentialStore(Credentials(server: server, token: "t", username: "demo"))
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testSaveDetectsLanguageWhenNotGiven() async throws {
        let transport = StubTransport([.json(TestJSON.snippet(4), status: 201)])
        _ = try await IntentActions.save(text: "print(1)", title: nil, language: nil,
                                         store: signedInStore(), transport: transport, detector: detector)
        let fragments = try XCTUnwrap(try body(transport.last)["fragments"] as? [[String: Any]])
        XCTAssertEqual(fragments[0]["language"] as? String, "python")
        XCTAssertEqual(try body(transport.last)["title"] as? String, "print(1)")
    }

    func testSaveUsesGivenLanguageAndTitle() async throws {
        let transport = StubTransport([.json(TestJSON.snippet(4), status: 201)])
        _ = try await IntentActions.save(text: "x", title: "Mine", language: "ruby",
                                         store: signedInStore(), transport: transport, detector: detector)
        let sent = try body(transport.last)
        XCTAssertEqual(sent["title"] as? String, "Mine")
        XCTAssertEqual((sent["fragments"] as? [[String: Any]])?.first?["language"] as? String, "ruby")
    }

    func testSaveSignedOutThrowsWithMessage() async {
        do {
            _ = try await IntentActions.save(text: "x", title: nil, language: nil,
                                             store: InMemoryCredentialStore(), transport: StubTransport(), detector: detector)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .signedOut)
            XCTAssertEqual(error.message, "Open ByteCatch and sign in first.")
        }
    }

    func testSaveUnauthorizedClearsTokenKeepsServer() async {
        let store = signedInStore()
        do {
            _ = try await IntentActions.save(text: "x", title: nil, language: nil, store: store,
                                             transport: StubTransport(status: 401), detector: detector)
        } catch {
            XCTAssertEqual(error, .signedOut)
        }
        _ = try? await IntentActions.save(text: "x", title: nil, language: nil, store: store,
                                          transport: StubTransport(status: 401), detector: detector)
        XCTAssertNil(store.load()?.token)
        XCTAssertEqual(store.load()?.server, server)
    }

    func testSaveRejectsEmptyText() async {
        do {
            _ = try await IntentActions.save(text: "  ", title: nil, language: nil, store: signedInStore(),
                                             transport: StubTransport(), detector: detector)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .emptyText)
            XCTAssertEqual(error.message, "There's no code to save.")
        }
    }

    func testSearchOnlineSendsTerm() async throws {
        let transport = StubTransport([.json(TestJSON.page([TestJSON.snippet(1, title: "curl")]))])
        let found = await IntentActions.search("curl", store: signedInStore(), transport: transport, cache: nil)
        XCTAssertEqual(found.map(\.title), ["curl"])
        let items = URLComponents(url: transport.last.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "search", value: "curl")))
    }

    func testSearchOfflineFallsBackToCache() async throws {
        let cache = try SnippetCache(inMemory: true)
        let cached = try JSONDecoder.byteStash.decode(Snippet.self, from: Data(TestJSON.snippet(2, title: "Docker prune").utf8))
        cache.store([cached], server: server)
        let found = await IntentActions.search("docker", store: signedInStore(),
                                               transport: StubTransport([.failure(URLError(.notConnectedToInternet))]), cache: cache)
        XCTAssertEqual(found.map(\.id), [2])
    }
}
