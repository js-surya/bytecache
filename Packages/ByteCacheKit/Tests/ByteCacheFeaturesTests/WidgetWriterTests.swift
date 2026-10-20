import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

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
        let (session, transport) = await TestSession.signedIn([.json(pinned), .json(recent), .json(recent)])
        let target = store()
        var reloads = 0
        let writer = WidgetSnapshotWriter(session: session, store: target, reload: { reloads += 1 })
        await writer.refresh()

        let queries = transport.requests.suffix(3).prefix(2).map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] }
        XCTAssertTrue(queries[0].contains(URLQueryItem(name: "pinned", value: "true")))
        XCTAssertFalse(queries[1].contains(URLQueryItem(name: "pinned", value: "true")))
        XCTAssertEqual(target.read()?.pinned.map(\.title), ["Pinned one"])
        XCTAssertEqual(target.read()?.recent.map(\.title), ["Newest", "Pinned one"])
        XCTAssertEqual(target.read()?.serverName, "x.io")
        XCTAssertEqual(reloads, 1)
    }

    /// CP-55: lists for the configurable widget.
    func testExtraListsForFavoritesSmartGroupsTagsAndLanguages() throws {
        func snippet(_ id: Int, _ title: String, language: String, tags: [String] = [], favorite: Bool = false) throws -> Snippet {
            var s = try JSONDecoder.byteStash.decode(Snippet.self, from: Data(TestJSON.snippet(id, title: title, language: language, categories: tags).utf8))
            s.isFavorite = favorite
            return s
        }
        let library = [try snippet(1, "Deploy", language: "bash", tags: ["Ops"], favorite: true),
                       try snippet(2, "Reader", language: "python", tags: ["io"])]
        let group = SmartGroup(name: "Python", rules: [SmartRule(field: .language, value: "python")])
        let (sources, lists) = WidgetSnapshotWriter.extraLists(library: library, smartGroups: [group])
        XCTAssertEqual(sources.map(\.title), ["Recent", "Pinned", "Favorites", "Python", "#io", "#ops", "Bash", "Python"])
        XCTAssertEqual(lists[WidgetSource.favorites.id]?.map(\.title), ["Deploy"])
        XCTAssertEqual(lists["smartGroup:\(group.id.uuidString)"]?.map(\.title), ["Reader"])
        XCTAssertEqual(lists["tag:ops"]?.map(\.title), ["Deploy"])
        XCTAssertEqual(lists["language:python"]?.map(\.title), ["Reader"])
        let snapshot = WidgetSnapshot(serverName: "x", pinned: [], recent: [], sources: sources, lists: lists)
        XCTAssertEqual(snapshot.list(for: WidgetSource(kind: .tag, value: "io", title: "#io")).map(\.title), ["Reader"])
        XCTAssertEqual(snapshot.snippet(id: 2)?.title, "Reader")
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
        let kept = WidgetSnippet(Snippet(id: 7, title: "Kept", description: "", updatedAt: nil, expiryDate: nil, isPublic: false,
                                         isPinned: false, isFavorite: false, categories: [], fragments: [], shareCount: 0))
        try target.write(WidgetSnapshot(serverName: "x.io", pinned: [], recent: [kept]))
        await WidgetSnapshotWriter(session: session, store: target, reload: {}).refresh()
        XCTAssertEqual(target.read()?.recent.map(\.title), ["Kept"])
        XCTAssertNil(target.read()?.problem)
    }

    /// CP-42: signed in but nothing loaded yet → the widget says the server can't be reached, not "sign in".
    func testOfflineWithNoSnapshotRecordsTheProblem() async {
        let (session, _) = await TestSession.signedIn([.failure(URLError(.notConnectedToInternet))])
        let target = store()
        var reloads = 0
        await WidgetSnapshotWriter(session: session, store: target, reload: { reloads += 1 }).refresh()
        XCTAssertEqual(target.read()?.problem, "Can't reach x.io")
        XCTAssertEqual(target.read()?.recent, [])
        XCTAssertEqual(reloads, 1)
    }

    func testSnapshotsFromEarlierVersionsStillDecode() throws {
        let old = #"{"serverName":"x.io","pinned":[],"recent":[],"updatedAt":0}"#
        XCTAssertNil(try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8)).problem)
    }
}
