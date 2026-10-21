import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// CP-66: each tab has its own list; a change made in one shows in the others straight away.
@MainActor
final class SharedListChangesTests: XCTestCase {
    private func ids(_ model: SnippetListModel) -> [Int] { model.snippets.map(\.id) }

    /// Two tabs on one session, loaded in order: `first` (All Snippets) then `second`.
    private func tabs(_ second: SidebarItem, firstPage: [String], secondPage: [String],
                      then replies: [StubTransport.Reply]) async -> (SnippetListModel, SnippetListModel) {
        let (session, _) = await TestSession.signedIn([.json(TestJSON.page(firstPage)), .json(TestJSON.page(secondPage))] + replies)
        let first = SnippetListModel(session: session, cache: nil)
        let other = SnippetListModel(session: session, cache: nil)
        other.selection = second
        await first.refresh()
        await other.refresh()
        return (first, other)
    }

    func testUnpinningInOneTabEmptiesThePinnedTab() async {
        let (all, pinned) = await tabs(.pinned,
            firstPage: [TestJSON.snippet(1, pinned: true), TestJSON.snippet(2, pinned: true), TestJSON.snippet(3)],
            secondPage: [TestJSON.snippet(1, pinned: true), TestJSON.snippet(2, pinned: true)],
            then: [.json("{}")])
        await all.togglePin(all.snippets.first { $0.id == 1 }!)
        XCTAssertEqual(ids(pinned), [2])
    }

    func testUnpinningInsideThePinnedTabRemovesTheRowAndUpdatesTheOthers() async {
        let (all, pinned) = await tabs(.pinned,
            firstPage: [TestJSON.snippet(1, pinned: true), TestJSON.snippet(2)],
            secondPage: [TestJSON.snippet(1, pinned: true)],
            then: [.json("{}")])
        await pinned.togglePin(pinned.snippets[0])
        XCTAssertEqual(ids(pinned), [])
        XCTAssertEqual(all.snippets.first { $0.id == 1 }?.isPinned, false)
    }

    func testFavoritingInOneTabAddsToTheFavoritesTab() async {
        let (all, favorites) = await tabs(.favorites,
            firstPage: [TestJSON.snippet(1), TestJSON.snippet(2)], secondPage: [],
            then: [.json("{}")])
        await all.toggleFavorite(all.snippets.first { $0.id == 2 }!)
        XCTAssertEqual(ids(favorites), [2])
        XCTAssertEqual(favorites.snippets.first?.isFavorite, true)
    }

    func testPinChangesShowInTheFavoritesSections() async {
        let (all, favorites) = await tabs(.favorites,
            firstPage: [TestJSON.snippet(1, pinned: true, favorite: true)],
            secondPage: [TestJSON.snippet(1, pinned: true, favorite: true)],
            then: [.json("{}")])
        XCTAssertEqual(favorites.pinnedSection.map(\.id), [1])
        await all.togglePin(all.snippets[0])
        XCTAssertEqual(favorites.pinnedSection.map(\.id), [])
        XCTAssertEqual(favorites.otherSection.map(\.id), [1], "moves from Pinned to Snippets in Favorites")
    }

    func testAFailedChangeLeavesTheOtherTabsAsTheyWere() async {
        let (all, pinned) = await tabs(.pinned,
            firstPage: [TestJSON.snippet(1, pinned: true)], secondPage: [TestJSON.snippet(1, pinned: true)],
            then: [.json("{}", status: 500)])
        await all.togglePin(all.snippets[0])
        XCTAssertEqual(ids(pinned), [1])
        XCTAssertEqual(pinned.snippets.first?.isPinned, true)
        XCTAssertNotNil(all.error)
    }

    func testBulkUnpinFromSelectUpdatesTheOtherTabs() async {
        let (all, pinned) = await tabs(.pinned,
            firstPage: [TestJSON.snippet(1, pinned: true), TestJSON.snippet(2, pinned: true)],
            secondPage: [TestJSON.snippet(1, pinned: true), TestJSON.snippet(2, pinned: true)],
            then: [.json("{}"), .json("{}")])
        pinned.isSelecting = true
        pinned.selectedIDs = [1, 2]
        await pinned.bulkSetPinned(false)
        XCTAssertEqual(ids(pinned), [])
        XCTAssertTrue(all.snippets.allSatisfy { !$0.isPinned })
    }

    func testRecyclingRemovesTheSnippetFromTheOtherTabs() async {
        let (all, favorites) = await tabs(.favorites,
            firstPage: [TestJSON.snippet(1, favorite: true), TestJSON.snippet(2)],
            secondPage: [TestJSON.snippet(1, favorite: true)],
            then: [.json("{}"), .json(TestJSON.snippet(1, favorite: true))])
        await all.recycle(all.snippets.first { $0.id == 1 }!)
        XCTAssertEqual(ids(favorites), [])
    }
}
