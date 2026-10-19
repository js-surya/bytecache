import XCTest
import ByteCatchCore
import ByteCatchTestSupport
@testable import ByteCatchFeatures

@MainActor
final class SnippetListModelTests: XCTestCase {
    private func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private func makeModel(_ replies: [StubTransport.Reply], cache: SnippetCache? = nil) async -> (SnippetListModel, StubTransport, SessionManager) {
        let (session, transport) = await TestSession.signedIn(replies)
        return (SnippetListModel(session: session, cache: cache, searchDelay: .milliseconds(20)), transport, session)
    }

    func testSidebarSelectionMapsToQuery() async {
        let (model, transport, _) = await makeModel([.json(TestJSON.page([]))])
        model.selection = .pinned; await model.refresh()
        XCTAssertEqual(query(transport.last)["pinned"], "true")
        model.selection = .language("go"); await model.refresh()
        XCTAssertEqual(query(transport.last)["language"], "go")
        model.selection = .recycleBin; await model.refresh()
        XCTAssertEqual(query(transport.last)["recycled"], "true")
        model.selection = .favorites; await model.refresh()
        XCTAssertEqual(query(transport.last)["favorites"], "true")
        model.selection = .category("Ops"); await model.refresh()
        XCTAssertEqual(query(transport.last)["category"], "ops")
    }

    func testSearchIsDebounced() async {
        let (model, transport, _) = await makeModel([.json(TestJSON.page([]))])
        let before = transport.requests.count
        model.searchText = "cu"
        model.searchTextChanged()
        model.searchText = "curl"
        model.searchTextChanged()
        await model.pendingSearch?.value
        XCTAssertEqual(transport.requests.count, before + 1)
        XCTAssertEqual(query(transport.last)["search"], "curl")
    }

    func testLoadMoreFetchesNextPageOnce() async {
        let first = TestJSON.page((1...50).map { TestJSON.snippet($0) }, total: 60)
        let second = TestJSON.page((51...60).map { TestJSON.snippet($0) }, total: 60, offset: 50)
        let (model, transport, _) = await makeModel([.json(first), .json(second)])
        await model.refresh()
        XCTAssertEqual(model.snippets.count, 50)

        let last = model.snippets.last!
        async let a: Void = model.loadMoreIfNeeded(current: last)
        async let b: Void = model.loadMoreIfNeeded(current: last)
        _ = await (a, b)
        XCTAssertEqual(model.snippets.count, 60)
        XCTAssertEqual(transport.requests.filter { query($0)["offset"] == "50" }.count, 1)

        let count = transport.requests.count
        await model.loadMoreIfNeeded(current: model.snippets.last!)
        XCTAssertEqual(transport.requests.count, count, "no more pages")
    }

    func testOfflineShowsCachedSnippets() async throws {
        let cache = try SnippetCache(inMemory: true)
        let cached = try JSONDecoder.byteStash.decode(Snippet.self, from: Data(TestJSON.snippet(7, title: "Cached").utf8))
        cache.store([cached], server: TestSession.server)
        let (model, _, _) = await makeModel([.failure(URLError(.notConnectedToInternet))], cache: cache)
        await model.refresh()
        XCTAssertTrue(model.isOffline)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.snippets.map(\.title), ["Cached"])
    }

    func testRefreshWritesCache() async throws {
        let cache = try SnippetCache(inMemory: true)
        let (model, _, _) = await makeModel([.json(TestJSON.page([TestJSON.snippet(1, title: "A")]))], cache: cache)
        await model.refresh()
        XCTAssertEqual(cache.snippet(id: 1, server: TestSession.server)?.title, "A")
    }

    func testUnauthorizedSignsOut() async {
        let (model, _, session) = await makeModel([.json("{}", status: 401), .json(#"{"authRequired":true}"#)])
        await model.refresh()
        guard case .needsLogin = session.state else { return XCTFail("\(session.state)") }
    }

    func testTogglePinIsOptimisticAndRollsBackOnFailure() async {
        let (model, _, _) = await makeModel([.json(TestJSON.page([TestJSON.snippet(1)])), .json("{}", status: 500)])
        await model.refresh()
        await model.togglePin(model.snippets[0])
        XCTAssertFalse(model.snippets[0].isPinned, "rolled back")
        XCTAssertEqual(model.error, "Server error (500)")
    }

    func testTogglePinSuccessUpdatesRow() async {
        let (model, transport, _) = await makeModel([.json(TestJSON.page([TestJSON.snippet(1)])), .json("{}")])
        await model.refresh()
        await model.togglePin(model.snippets[0])
        XCTAssertTrue(model.snippets[0].isPinned)
        XCTAssertEqual(transport.last.url?.path, "/api/snippets/1/pin")
    }

    func testRecycleRemovesRow() async {
        let page = TestJSON.page([TestJSON.snippet(1), TestJSON.snippet(2)])
        let (model, _, _) = await makeModel([.json(page), .json("{}")])
        await model.refresh()
        await model.recycle(model.snippets[0])
        XCTAssertEqual(model.snippets.map(\.id), [2])
    }
}

@MainActor
final class PinnedOrderTests: XCTestCase {
    private func ids(_ model: SnippetListModel) -> [Int] { model.snippets.map(\.id) }

    func testPinningMovesToTopAndUnpinningMovesBelowPinned() async {
        let page = TestJSON.page([TestJSON.snippet(1, pinned: true), TestJSON.snippet(2), TestJSON.snippet(3)])
        let (session, _) = await TestSession.signedIn([.json(page), .json("{}")])
        let model = SnippetListModel(session: session, cache: nil)
        await model.refresh()
        await model.togglePin(model.snippets[2])
        XCTAssertEqual(ids(model), [3, 1, 2], "newly pinned goes to the top")
        await model.togglePin(model.snippets[0])
        XCTAssertEqual(ids(model), [1, 3, 2], "unpinned goes below the pinned ones")
    }

    func testPinnedSplitForSections() async {
        let page = TestJSON.page([TestJSON.snippet(1, pinned: true), TestJSON.snippet(2)])
        let (session, _) = await TestSession.signedIn([.json(page)])
        let model = SnippetListModel(session: session, cache: nil)
        await model.refresh()
        XCTAssertEqual(model.pinnedSection.map(\.id), [1])
        XCTAssertEqual(model.otherSection.map(\.id), [2])
        model.selection = .pinned
        XCTAssertTrue(model.pinnedSection.isEmpty, "no Pinned header inside the Pinned list itself")
        XCTAssertEqual(model.otherSection.map(\.id), [1, 2])
    }

    func testOfflineCacheListsPinnedFirst() async throws {
        let cache = try SnippetCache(inMemory: true)
        let decoder = JSONDecoder.byteStash
        let older = try decoder.decode(Snippet.self, from: Data(TestJSON.snippet(1, pinned: true).utf8))
        var newer = try decoder.decode(Snippet.self, from: Data(TestJSON.snippet(2).utf8))
        newer.updatedAt = Date()
        cache.store([older, newer], server: TestSession.server)
        XCTAssertEqual(cache.all(server: TestSession.server, matching: SnippetQuery()).map(\.id), [1, 2])
    }
}

@MainActor
final class SnippetRevealTests: XCTestCase {
    func testRevealFetchesMissingSnippet() async {
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.page([TestJSON.snippet(1)])), .json(TestJSON.snippet(99, title: "Far"))])
        let model = SnippetListModel(session: session, cache: nil)
        await model.refresh()
        let found = await model.reveal(id: 99)
        XCTAssertTrue(found)
        XCTAssertEqual(model.snippets.first?.title, "Far")
        XCTAssertEqual(transport.last.url?.path, "/api/snippets/99")
    }

    func testRevealKnownSnippetDoesNotFetch() async {
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.page([TestJSON.snippet(1)]))])
        let model = SnippetListModel(session: session, cache: nil)
        await model.refresh()
        let count = transport.requests.count
        let found = await model.reveal(id: 1)
        XCTAssertTrue(found)
        XCTAssertEqual(transport.requests.count, count)
    }
}

@MainActor
final class SidebarModelTests: XCTestCase {
    func testLoadsLanguagesAndCategoriesSorted() async {
        let meta = #"{"categories":["web","api"],"languages":["python","bash"]}"#
        let (session, _) = await TestSession.signedIn([.json(meta)])
        let model = SidebarModel(session: session)
        await model.load()
        XCTAssertEqual(model.languages, ["bash", "python"])
        XCTAssertEqual(model.categories, ["api", "web"])
    }
}

@MainActor
final class MostUsedListTests: XCTestCase {
    func testMostUsedLoadsSnippetsInUsageOrder() async throws {
        let name = "bytecatch.mu.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let usage = UsageTracker(defaults: UserDefaults(suiteName: name)!)
        usage.recordCopy(snippetID: 7, server: TestSession.server)
        usage.recordCopy(snippetID: 9, server: TestSession.server)
        usage.recordCopy(snippetID: 9, server: TestSession.server)
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.snippet(9, title: "Nine")), .json(TestJSON.snippet(7, title: "Seven"))])
        let model = SnippetListModel(session: session, cache: nil, usage: usage)
        model.selection = .mostUsed
        await model.refresh()
        XCTAssertEqual(model.snippets.map(\.title), ["Nine", "Seven"])
        XCTAssertEqual(transport.requests.suffix(2).compactMap(\.url?.path), ["/api/snippets/9", "/api/snippets/7"])
        XCTAssertEqual(SidebarItem.mostUsed.title, "Most Used")
    }
}
