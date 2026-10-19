import XCTest
import ByteCatchCore
import ByteCatchTestSupport
@testable import ByteCatchFeatures

@MainActor
final class WidgetWriterTests: XCTestCase {
    private func store() -> WidgetSnapshotStore {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return WidgetSnapshotStore(directory: dir)
    }

    func testFetchesPinnedAndRecentAndWrites() async {
        let pinned = TestJSON.page([TestJSON.snippet(1, title: "Pinned one", pinned: true)])
        let recent = TestJSON.page([TestJSON.snippet(2, title: "Newest"), TestJSON.snippet(1, title: "Pinned one", pinned: true)])
        let (session, transport) = await TestSession.signedIn([.json(pinned), .json(recent)])
        let target = store()
        var reloads = 0
        let writer = WidgetSnapshotWriter(session: session, store: target, reload: { reloads += 1 })
        await writer.refresh()

        let queries = transport.requests.suffix(2).map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] }
        XCTAssertTrue(queries[0].contains(URLQueryItem(name: "pinned", value: "true")))
        XCTAssertFalse(queries[1].contains(URLQueryItem(name: "pinned", value: "true")))
        XCTAssertEqual(target.read()?.pinned.map(\.title), ["Pinned one"])
        XCTAssertEqual(target.read()?.recent.map(\.title), ["Newest", "Pinned one"])
        XCTAssertEqual(target.read()?.serverName, "x.io")
        XCTAssertEqual(reloads, 1)
    }

    func testSignedOutClearsSnapshot() async throws {
        let (session, _) = await TestSession.signedIn([.json(TestJSON.page([])), .json(TestJSON.page([]))])
        let target = store()
        try target.write(WidgetSnapshot(serverName: "old", pinned: [], recent: []))
        session.signOut()
        await WidgetSnapshotWriter(session: session, store: target, reload: {}).refresh()
        XCTAssertNil(target.read())
    }

    func testOfflineKeepsLastSnapshot() async throws {
        let (session, _) = await TestSession.signedIn([.failure(URLError(.notConnectedToInternet))])
        let target = store()
        try target.write(WidgetSnapshot(serverName: "kept", pinned: [], recent: []))
        await WidgetSnapshotWriter(session: session, store: target, reload: {}).refresh()
        XCTAssertEqual(target.read()?.serverName, "kept")
    }
}
