import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// Opening a snippet from a widget, Spotlight or Handoff while the list is still loading must not show
/// that snippet twice (seen on iPad: the first page arrived while the snippet was being fetched).
@MainActor
final class RevealRaceTests: XCTestCase {
    /// Answers the list at once, but holds the single-snippet request until `release()`.
    final class GatedTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: CheckedContinuation<Void, Never>?
        private var released = false

        func release() {
            lock.lock(); released = true; let w = waiting; waiting = nil; lock.unlock()
            w?.resume()
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let path = request.url?.path() ?? ""
            let body: String
            if path.hasSuffix("/auth/verify") {
                body = TestJSON.verify
            } else if path == "/api/snippets/18" {
                await withCheckedContinuation { continuation in
                    lock.lock()
                    if released { lock.unlock(); continuation.resume() } else { waiting = continuation; lock.unlock() }
                }
                body = TestJSON.snippet(18)
            } else {
                body = TestJSON.page([TestJSON.snippet(17), TestJSON.snippet(18), TestJSON.snippet(19)])
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            return (Data(body.utf8), response)
        }
    }

    func testOpeningASnippetWhileTheListLoadsShowsItOnce() async throws {
        let transport = GatedTransport()
        let session = SessionManager(store: InMemoryCredentialStore(Credentials(server: TestSession.server, token: "t", username: "demo")),
                                     transport: transport)
        await session.restore()
        let list = SnippetListModel(session: session, cache: nil)

        let reveal = Task { await list.reveal(id: 18) }   // list empty: fetches snippet 18…
        try await Task.sleep(for: .milliseconds(50))
        await list.refresh()                               // …while the first page (with 18) arrives
        transport.release()
        let found = await reveal.value

        XCTAssertTrue(found)
        XCTAssertEqual(list.snippets.map(\.id).filter { $0 == 18 }.count, 1, "\(list.snippets.map(\.id))")
    }
}
