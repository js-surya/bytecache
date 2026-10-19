import XCTest
import ByteCatchCore
import ByteCatchLanguage
import ByteCatchTestSupport
@testable import ByteCatchFeatures

@MainActor
final class SaveQueueTests: XCTestCase {
    private func store() -> PendingSaveQueue {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return PendingSaveQueue(directory: dir)
    }

    func testCaptureOfflineIsQueued() async throws {
        let queue = store()
        let client = APIClient(server: TestSession.server, token: "t", transport: StubTransport([.failure(URLError(.notConnectedToInternet))]))
        let model = CaptureModel(text: "ls -la", client: client, detector: .rulesOnly, queue: queue)
        do {
            _ = try await model.save()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error, .offline)
        }
        XCTAssertTrue(model.didQueue)
        XCTAssertEqual(queue.items(for: TestSession.server).first?.draft.fragments.first?.code, "ls -la")
    }

    func testFlushUploadsInOrderAndStopsWhenOffline() async throws {
        let queue = store()
        for title in ["one", "two", "three"] {
            try queue.enqueue(SnippetDraft(title: title, description: "", categories: [],
                                           fragments: [FragmentDraft(fileName: "a", code: title, language: "bash")], isPublic: false),
                              server: TestSession.server)
        }
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.snippet(1), status: 201),
                                                               .failure(URLError(.notConnectedToInternet))])
        let flusher = SaveQueueFlusher(session: session, queue: queue)
        let uploaded = await flusher.flush()
        XCTAssertEqual(uploaded, 1)
        XCTAssertEqual(queue.items(for: TestSession.server).map(\.draft.title), ["two", "three"])
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 2, "tried one more, then stopped")
    }

    func testFlushEverythingWhenOnline() async throws {
        let queue = store()
        try queue.enqueue(SnippetDraft(title: "a", description: "", categories: [],
                                       fragments: [FragmentDraft(fileName: "a", code: "a", language: "bash")], isPublic: false),
                          server: TestSession.server)
        let (session, _) = await TestSession.signedIn([.json(TestJSON.snippet(1), status: 201)])
        let uploaded = await SaveQueueFlusher(session: session, queue: queue).flush()
        XCTAssertEqual(uploaded, 1)
        XCTAssertEqual(queue.count, 0)
    }

    func testIntentOfflineIsQueuedWithFriendlyResult() async throws {
        let queue = store()
        let creds = InMemoryCredentialStore(Credentials(server: TestSession.server, token: "t"))
        do {
            _ = try await IntentActions.save(text: "ls", title: nil, language: nil, store: creds,
                                             transport: StubTransport([.failure(URLError(.notConnectedToInternet))]),
                                             detector: .rulesOnly, queue: queue)
            XCTFail("expected queued")
        } catch {
            XCTAssertEqual(error, .queued)
            XCTAssertEqual(error.message, "You're offline, so ByteCatch saved this on your device. It uploads automatically when you're back online.")
        }
        XCTAssertEqual(queue.count, 1)
    }
}
