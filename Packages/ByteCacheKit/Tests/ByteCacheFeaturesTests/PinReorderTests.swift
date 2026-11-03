import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// CP-99: dragging pins into order keeps it in settings, and every list follows.
@MainActor
final class PinReorderTests: XCTestCase {
    private func ids(_ model: SnippetListModel) -> [Int] { model.snippets.map(\.id) }

    func testMovingPinsReordersEveryListAndUnpinningForgetsTheSnippet() async {
        let page = TestJSON.page([TestJSON.snippet(1, pinned: true), TestJSON.snippet(2, pinned: true),
                                  TestJSON.snippet(3, pinned: true), TestJSON.snippet(4)])
        let pinnedPage = TestJSON.page([TestJSON.snippet(1, pinned: true), TestJSON.snippet(2, pinned: true),
                                        TestJSON.snippet(3, pinned: true)])
        let (session, _) = await TestSession.signedIn([.json(page), .json(pinnedPage), .json("{}")])
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!, aiKeys: MemoryAIKeyStore())
        let all = SnippetListModel(session: session, cache: nil, settings: settings)
        let pinned = SnippetListModel(session: session, cache: nil, settings: settings)
        pinned.selection = .pinned
        await all.refresh()
        await pinned.refresh()
        XCTAssertTrue(pinned.canReorderPins)

        // Drag the last pin to the top of the Pinned list.
        pinned.movePins(from: [2], to: 0)
        XCTAssertEqual(settings.pinOrders.order(server: TestSession.server), [3, 1, 2])
        XCTAssertEqual(ids(pinned), [3, 1, 2])
        XCTAssertEqual(all.pinnedSection.map(\.id), [3, 1, 2])
        XCTAssertEqual(all.otherSection.map(\.id), [4])

        await all.togglePin(all.snippets.first { $0.id == 1 }!)
        XCTAssertEqual(settings.pinOrders.order(server: TestSession.server), [3, 2])

        // Searching ranks results, so no reordering then.
        pinned.searchText = "x"
        XCTAssertFalse(pinned.canReorderPins)
    }

    func testPinOrderSyncs() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!, aiKeys: MemoryAIKeyStore())
        var orders = PinOrders()
        orders.set([5, 4], server: TestSession.server)
        var remote = settings.synced
        remote.pinOrders = orders
        settings.apply(remote)
        XCTAssertEqual(settings.synced.pinOrders, orders)
    }
}
