import XCTest
@testable import ByteCacheFeatures

@MainActor
final class TipJarTests: XCTestCase {
    private struct FakeStore: TipStore {
        var tips: [Tip] = [
            Tip(id: "large", name: "Large Tip", price: "$2.99", sortPrice: 2.99),
            Tip(id: "small", name: "Small Tip", price: "$0.99", sortPrice: 0.99),
            Tip(id: "medium", name: "Medium Tip", price: "$1.99", sortPrice: 1.99),
        ]
        var outcome: Result<TipOutcome, TipJarError> = .success(.thanked)
        var fails = false
        var tippedBefore = false

        func tips() async throws -> [Tip] {
            if fails { throw TipJarError.unavailable }
            return tips
        }

        func buy(_ id: String) async throws -> TipOutcome { try outcome.get() }

        func hasTipped() async -> Bool { tippedBefore }
    }

    func testTipsAreSortedCheapestFirst() async {
        let model = TipJarModel(store: FakeStore())
        await model.load()
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.tips.map(\.id), ["small", "medium", "large"])
    }

    func testNoTipsHidesTheJar() async {
        let empty = TipJarModel(store: FakeStore(tips: []))
        await empty.load()
        XCTAssertEqual(empty.state, .unavailable)

        let failing = TipJarModel(store: FakeStore(fails: true))
        await failing.load()
        XCTAssertEqual(failing.state, .unavailable)
    }

    func testOutcomes() async {
        let tip = Tip(id: "small", name: "Small Tip", price: "$0.99", sortPrice: 0.99)

        let thanked = TipJarModel(store: FakeStore())
        await thanked.buy(tip)
        XCTAssertTrue(thanked.isSupporter)
        XCTAssertNil(thanked.buying)

        let pending = TipJarModel(store: FakeStore(outcome: .success(.pending)))
        await pending.buy(tip)
        XCTAssertTrue(pending.showsPending)
        XCTAssertFalse(pending.isSupporter)

        let cancelled = TipJarModel(store: FakeStore(outcome: .success(.cancelled)))
        await cancelled.buy(tip)
        XCTAssertFalse(cancelled.isSupporter)
        XCTAssertNil(cancelled.errorMessage)

        let failed = TipJarModel(store: FakeStore(outcome: .failure(.unverified)))
        await failed.buy(tip)
        XCTAssertNotNil(failed.errorMessage)
        XCTAssertFalse(failed.isSupporter)
    }

    func testSupporterComesFromPurchaseHistoryAndNewTips() async {
        let past = TipJarModel(store: FakeStore(tippedBefore: true))
        await past.load()
        XCTAssertTrue(past.isSupporter)

        let fresh = TipJarModel(store: FakeStore())
        await fresh.load()
        XCTAssertFalse(fresh.isSupporter)
        await fresh.buy(fresh.tips[0])
        XCTAssertTrue(fresh.isSupporter)
        XCTAssertEqual(fresh.celebrations, 1)

        let cancelled = TipJarModel(store: FakeStore(outcome: .success(.cancelled)))
        await cancelled.load()
        await cancelled.buy(cancelled.tips[0])
        XCTAssertFalse(cancelled.isSupporter)
        XCTAssertEqual(cancelled.celebrations, 0)
    }

    func testProductIDs() {
        XCTAssertEqual(TipJar.productIDs.count, 3)
        XCTAssertEqual(Set(TipJar.productIDs).count, 3)
        XCTAssertTrue(TipJar.productIDs.allSatisfy { $0.hasPrefix("me.suryajs.bytecache.tip.") })
    }
}
