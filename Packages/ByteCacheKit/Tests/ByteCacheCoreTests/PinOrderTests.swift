import XCTest
@testable import ByteCacheCore

final class PinOrderTests: XCTestCase {
    private func snippet(_ id: Int, _ title: String, pinned: Bool) -> Snippet {
        Snippet(id: id, title: title, description: "", updatedAt: nil, expiryDate: nil, isPublic: false,
                isPinned: pinned, isFavorite: false, categories: [], fragments: [], shareCount: 0)
    }

    func testPinsFollowTheOrderAndNewPinsGoFirst() {
        let list = [snippet(1, "a", pinned: true), snippet(2, "b", pinned: true), snippet(3, "c", pinned: true),
                    snippet(4, "d", pinned: false), snippet(5, "e", pinned: true)]
        // 5 is a new pin: on top. The rest of the pins follow the order; unpinned by the sort.
        let arranged = SnippetOrdering.arranged(list, by: .alphaAsc, pinOrder: [3, 1, 2])
        XCTAssertEqual(arranged.map(\.id), [5, 3, 1, 2, 4])
        // No order: the sort, as before.
        XCTAssertEqual(SnippetOrdering.arranged(list, by: .alphaDesc).map(\.id), [5, 3, 2, 1, 4])
        // An unpinned snippet still in the order doesn't jump ahead.
        XCTAssertEqual(SnippetOrdering.arranged(list, by: .alphaAsc, pinOrder: [4, 2]).map(\.id), [1, 3, 5, 2, 4])
    }

    func testMovedMatchesOnMove() {
        XCTAssertEqual(PinOrders.moved([1, 2, 3, 4], from: [0], to: 3), [2, 3, 1, 4])
        XCTAssertEqual(PinOrders.moved([1, 2, 3, 4], from: [3], to: 0), [4, 1, 2, 3])
        XCTAssertEqual(PinOrders.moved([1, 2, 3, 4], from: [1], to: 4), [1, 3, 4, 2])
        XCTAssertEqual(PinOrders.moved([1, 2, 3, 4], from: [0, 2], to: 4), [2, 4, 1, 3])
    }

    func testMovingAFilteredListKeepsHiddenPinsInPlace() {
        // Stored 1 2 3 4 5; the list shows only 2 and 4 (say, one tag) plus new pin 9 on top.
        XCTAssertEqual(PinOrders.moving([9, 2, 4], in: [1, 2, 3, 4, 5], from: [2], to: 0), [4, 1, 9, 3, 2, 5])
        XCTAssertEqual(PinOrders.moving([1, 2, 3], in: [], from: [0], to: 3), [2, 3, 1])
    }

    func testOrdersArePerServer() throws {
        let a = try ServerURL("https://a.io"), b = try ServerURL("https://b.io")
        var orders = PinOrders()
        orders.set([2, 1], server: a)
        XCTAssertEqual(orders.order(server: a), [2, 1])
        XCTAssertEqual(orders.order(server: b), [])
        orders.remove(2, server: a)
        XCTAssertEqual(orders.order(server: a), [1])
        orders.set([], server: a)
        XCTAssertEqual(orders, PinOrders())
    }
}
