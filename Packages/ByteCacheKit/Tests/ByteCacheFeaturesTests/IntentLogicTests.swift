import XCTest
import ByteCacheCore
import ByteCacheLanguage
import ByteCacheTestSupport
@testable import ByteCacheFeatures

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
            XCTAssertEqual(error.message, "Open ByteCache and sign in first.")
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

/// CP-52: Find Snippets and Get Snippet Code for Shortcuts.
@MainActor
final class ShortcutActionTests: XCTestCase {
    private let server = TestSession.server

    private func signedInStore() -> InMemoryCredentialStore {
        InMemoryCredentialStore(Credentials(server: server, token: "t", username: "demo"))
    }

    private func items(_ request: URLRequest) -> [URLQueryItem] {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    func testFindPassesTextLanguageAndTag() async throws {
        let transport = StubTransport([.json(TestJSON.page([TestJSON.snippet(3, title: "Reader")]))])
        let found = try await IntentActions.find("reader #files", language: "Python", tag: "io",
                                                 store: signedInStore(), transport: transport, cache: nil, isLocked: false)
        XCTAssertEqual(found.map(\.title), ["Reader"])
        let query = items(transport.last)
        XCTAssertTrue(query.contains(URLQueryItem(name: "search", value: "reader")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "language", value: "python")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "category", value: "io,files")))
    }

    func testCodeReturnsAllFilesOrTheFirst() async throws {
        let json = TestJSON.snippet(5, code: "first")
        let transport = StubTransport([.json(json), .json(json)])
        let all = try await IntentActions.code(ofSnippet: 5, allFiles: true, store: signedInStore(),
                                               transport: transport, cache: nil, isLocked: false)
        XCTAssertEqual(all, "first")
        XCTAssertEqual(transport.last.url?.path, "/api/snippets/5")
        let first = try await IntentActions.code(ofSnippet: 5, allFiles: false, store: signedInStore(),
                                                 transport: transport, cache: nil, isLocked: false)
        XCTAssertEqual(first, "first")
    }

    func testLockedAndSignedOutAreRefused() async {
        do {
            _ = try await IntentActions.code(ofSnippet: 1, allFiles: true, store: signedInStore(),
                                             transport: StubTransport([]), cache: nil, isLocked: true)
            XCTFail("expected locked")
        } catch { XCTAssertEqual(error, .locked) }
        do {
            _ = try await IntentActions.find("x", store: InMemoryCredentialStore(), transport: StubTransport([]),
                                             cache: nil, isLocked: false)
            XCTFail("expected signed out")
        } catch { XCTAssertEqual(error, .signedOut) }
    }
}
