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

        func tips() async throws -> [Tip] {
            if fails { throw TipJarError.unavailable }
            return tips
        }

        func buy(_ id: String) async throws -> TipOutcome { try outcome.get() }
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
        XCTAssertTrue(thanked.showsThanks)
        XCTAssertNil(thanked.buying)

        let pending = TipJarModel(store: FakeStore(outcome: .success(.pending)))
        await pending.buy(tip)
        XCTAssertTrue(pending.showsPending)
        XCTAssertFalse(pending.showsThanks)

        let cancelled = TipJarModel(store: FakeStore(outcome: .success(.cancelled)))
        await cancelled.buy(tip)
        XCTAssertFalse(cancelled.showsThanks)
        XCTAssertNil(cancelled.errorMessage)

        let failed = TipJarModel(store: FakeStore(outcome: .failure(.unverified)))
        await failed.buy(tip)
        XCTAssertNotNil(failed.errorMessage)
        XCTAssertFalse(failed.showsThanks)
    }

    func testProductIDs() {
        XCTAssertEqual(TipJar.productIDs.count, 3)
        XCTAssertEqual(Set(TipJar.productIDs).count, 3)
        XCTAssertTrue(TipJar.productIDs.allSatisfy { $0.hasPrefix("me.suryajs.bytecache.tip.") })
    }
}
