import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

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

    /// Pinning moves a snippet into the pinned group at its sorted place (where a refresh would show it).
    func testPinningJoinsPinnedGroupInSortOrder() async {
        let page = TestJSON.page([TestJSON.snippet(1, title: "b", pinned: true), TestJSON.snippet(2, title: "c"),
                                  TestJSON.snippet(3, title: "a")])
        let (session, _) = await TestSession.signedIn([.json(page), .json("{}"), .json("{}")])
        let model = SnippetListModel(session: session, cache: nil)
        model.sort = .alphaAsc
        await model.refresh()
        XCTAssertEqual(ids(model), [1, 3, 2])
        await model.togglePin(model.snippets[1])
        XCTAssertEqual(ids(model), [3, 1, 2], "pinned 'a' sorts before pinned 'b'")
        await model.togglePin(model.snippets[0])
        XCTAssertEqual(ids(model), [1, 3, 2], "unpinned 'a' goes below the pinned ones")
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
        let name = "bytecache.mu.\(UUID().uuidString)"
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

@MainActor
final class PublicSnippetsTests: XCTestCase {
    func testPublicSectionUsesPublicEndpointAndIsReadOnly() async {
        let page = TestJSON.page([TestJSON.snippet(5, title: "Shared", isPublic: true)])
        let (session, transport) = await TestSession.signedIn([.json(page)])
        let model = SnippetListModel(session: session, cache: nil)
        model.selection = .publicSnippets
        await model.refresh()
        XCTAssertEqual(transport.last.url?.path, "/api/public/snippets")
        XCTAssertEqual(model.snippets.map(\.title), ["Shared"])
        XCTAssertTrue(model.isReadOnly)
        model.selection = .all
        XCTAssertFalse(model.isReadOnly)
    }

    func testMakePublicSendsFullSnippet() async throws {
        let page = TestJSON.page([TestJSON.snippet(3, code: "echo hi", categories: ["ops"])])
        let (session, transport) = await TestSession.signedIn([.json(page), .json(TestJSON.snippet(3, isPublic: true, categories: ["ops"]))])
        let model = SnippetListModel(session: session, cache: nil)
        await model.refresh()
        await model.setPublic(model.snippets[0], true)
        XCTAssertEqual(transport.last.httpMethod, "PUT")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(transport.last.httpBody)) as? [String: Any])
        XCTAssertEqual(body["is_public"] as? Int, 1)
        XCTAssertEqual(body["categories"] as? [String], ["ops"])
        XCTAssertEqual((body["fragments"] as? [[String: Any]])?.first?["code"] as? String, "echo hi")
        XCTAssertTrue(model.snippets[0].isPublic)
    }

    func testOwnerNameDecodes() throws {
        let json = TestJSON.snippet(1).replacingOccurrences(of: #""share_count":0"#, with: #""share_count":0,"username":"alice""#)
        let snippet = try JSONDecoder.byteStash.decode(Snippet.self, from: Data(json.utf8))
        XCTAssertEqual(snippet.username, "alice")
    }
}

@MainActor
final class BulkActionTests: XCTestCase {
    private func bodies(_ transport: StubTransport) -> [[String: Any]] {
        transport.requests.compactMap { $0.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }

    func testBulkPinOnlyChangesThoseThatNeedIt() async {
        let page = TestJSON.page([TestJSON.snippet(1, pinned: true), TestJSON.snippet(2), TestJSON.snippet(3)])
        let (session, transport) = await TestSession.signedIn([.json(page), .json("{}")])
        let model = SnippetListModel(session: session, cache: nil)
        await model.refresh()
        model.isSelecting = true
        model.selectedIDs = [1, 2, 3]
        let before = transport.requests.count
        await model.bulkSetPinned(true)
        XCTAssertEqual(transport.requests.count - before, 2, "1 was already pinned")
        XCTAssertTrue(model.snippets.allSatisfy(\.isPinned))
        XCTAssertFalse(model.isSelecting)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testAddAndRemoveCategorySaveWholeSnippets() async throws {
        let page = TestJSON.page([TestJSON.snippet(1, code: "a", categories: ["web"]), TestJSON.snippet(2, code: "b")])
        let (session, transport) = await TestSession.signedIn([.json(page), .json(TestJSON.snippet(1, categories: ["web", "ops"])),
                                                               .json(TestJSON.snippet(2, categories: ["ops"]))])
        let model = SnippetListModel(session: session, cache: nil)
        await model.refresh()
        model.selectedIDs = [1, 2]
        await model.bulkAddCategory(" Ops ")
        let puts = transport.requests.filter { $0.httpMethod == "PUT" }
        XCTAssertEqual(puts.count, 2)
        let sent = bodies(transport).suffix(2)
        XCTAssertEqual(sent.first?["categories"] as? [String], ["web", "ops"])
        XCTAssertEqual((sent.first?["fragments"] as? [[String: Any]])?.first?["code"] as? String, "a")
        XCTAssertEqual(sent.last?["categories"] as? [String], ["ops"])

        let (session2, transport2) = await TestSession.signedIn([.json(page), .json(TestJSON.snippet(1))])
        let model2 = SnippetListModel(session: session2, cache: nil)
        await model2.refresh()
        model2.selectedIDs = [1, 2]
        await model2.bulkRemoveCategory("web")
        XCTAssertEqual(transport2.requests.filter { $0.httpMethod == "PUT" }.count, 1, "only snippets that have it")
    }

    func testBulkRecycleRemovesRows() async {
        let page = TestJSON.page([TestJSON.snippet(1), TestJSON.snippet(2), TestJSON.snippet(3)])
        let (session, _) = await TestSession.signedIn([.json(page), .json("{}")])
        let model = SnippetListModel(session: session, cache: nil)
        await model.refresh()
        model.selectedIDs = [1, 3]
        await model.bulkRecycle()
        XCTAssertEqual(model.snippets.map(\.id), [2])
    }
}

/// CP-28: Suggest Title for untitled snippets.
@MainActor
final class SuggestTitleTests: XCTestCase {
    func testUntitledSnippetsNeedATitle() throws {
        let decode = { (title: String) in try JSONDecoder.byteStash.decode(Snippet.self, from: Data(TestJSON.snippet(1, title: title).utf8)) }
        XCTAssertTrue(try decode("").needsTitle)
        XCTAssertTrue(try decode(" Untitled Snippet ").needsTitle)
        XCTAssertFalse(try decode("CSV Reader").needsTitle)
    }

    func testRenameSendsFullSnippetWithNewTitle() async throws {
        let page = TestJSON.page([TestJSON.snippet(3, title: "", code: "echo hi", categories: ["ops"])])
        let (session, transport) = await TestSession.signedIn([.json(page), .json(TestJSON.snippet(3, title: "Say Hi", code: "echo hi", categories: ["ops"]))])
        let model = SnippetListModel(session: session, cache: nil)
        await model.refresh()
        await model.rename(model.snippets[0], to: "  Say Hi ")
        XCTAssertEqual(transport.last.httpMethod, "PUT")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(transport.last.httpBody)) as? [String: Any])
        XCTAssertEqual(body["title"] as? String, "Say Hi")
        XCTAssertEqual(body["categories"] as? [String], ["ops"])
        XCTAssertEqual((body["fragments"] as? [[String: Any]])?.first?["code"] as? String, "echo hi")
        XCTAssertEqual(model.snippets[0].title, "Say Hi")
    }
}

/// CP-46: typed filters and close matches.
@MainActor
final class SearchFilterTests: XCTestCase {
    private func items(_ request: URLRequest) -> [URLQueryItem] {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    func testTypedFiltersReachTheServerQuery() async {
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.page([]))])
        let model = SnippetListModel(session: session, cache: nil)
        model.knownLanguages = ["Python"]
        model.searchText = "reader lang:python #io is:pinned"
        await model.refresh()
        let query = items(transport.last)
        XCTAssertTrue(query.contains(URLQueryItem(name: "search", value: "reader")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "language", value: "Python")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "pinned", value: "true")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "category", value: "io")))
    }

    func testSelectedLanguageWinsOverTypedOne() async {
        let (session, _) = await TestSession.signedIn([])
        let model = SnippetListModel(session: session, cache: nil)
        model.selection = .language("bash")
        model.searchText = "lang:python"
        XCTAssertEqual(model.query.language, "bash")
        XCTAssertNil(model.query.search)
    }

    func testNoExactMatchShowsCloseMatchesFromTheCache() async throws {
        let cache = try SnippetCache(inMemory: true)
        let (session, _) = await TestSession.signedIn([.json(TestJSON.page([]))])
        let reader = try JSONDecoder.byteStash.decode(Snippet.self, from: Data(TestJSON.snippet(4, title: "CSV Reader").utf8))
        cache.store([reader], server: session.client!.server)
        let model = SnippetListModel(session: session, cache: cache)
        model.searchText = "csvrd"
        await model.refresh()
        XCTAssertTrue(model.showsCloseMatches)
        XCTAssertEqual(model.snippets.map(\.title), ["CSV Reader"])
    }
}

/// CP-47: Smart Groups load every snippet and filter on the device.
@MainActor
final class SmartGroupListTests: XCTestCase {
    func testLoadsAllPagesAndFiltersByTheRules() async {
        let first = TestJSON.page([TestJSON.snippet(1, title: "Shell tip", language: "bash"),
                                   TestJSON.snippet(2, title: "CSV reader", language: "python")], total: 3, limit: 2)
        let second = TestJSON.page([TestJSON.snippet(3, title: "Python setup", language: "python")], total: 3, offset: 2)
        let (session, transport) = await TestSession.signedIn([.json(first), .json(second), .json(first), .json(second)])
        let model = SnippetListModel(session: session, cache: nil)
        let group = SmartGroup(name: "Python", rules: [SmartRule(field: .language, value: "python")])
        model.smartGroups = [group]
        model.selection = .smartGroup(group.id)
        await model.refresh()
        XCTAssertEqual(Set(model.snippets.map(\.id)), [2, 3])
        XCTAssertEqual(model.title, "Python")
        XCTAssertEqual(transport.requests.compactMap { $0.url?.path }.filter { $0 == "/api/snippets" }.count, 2)

        model.searchText = "csv"
        await model.refresh()
        XCTAssertEqual(model.snippets.map(\.id), [2])
    }

    func testMissingGroupShowsNothing() async {
        let (session, _) = await TestSession.signedIn([])
        let model = SnippetListModel(session: session, cache: nil)
        model.selection = .smartGroup(UUID())
        await model.refresh()
        XCTAssertEqual(model.snippets, [])
        XCTAssertEqual(model.title, "Smart Group")
    }
}
