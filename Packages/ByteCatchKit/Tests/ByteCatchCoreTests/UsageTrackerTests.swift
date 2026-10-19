import XCTest
@testable import ByteCatchCore

final class UsageTrackerTests: XCTestCase {
    private func tracker() -> UsageTracker {
        let name = "bytecatch.usage.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return UsageTracker(defaults: UserDefaults(suiteName: name)!)
    }

    private let a = try! ServerURL("https://a.io")
    private let b = try! ServerURL("https://b.io")

    func testCountsOrderAndTieBreakByMostRecent() {
        let usage = tracker()
        var now = Date(timeIntervalSince1970: 1_000)
        usage.recordCopy(snippetID: 1, server: a, at: now)
        now += 10; usage.recordCopy(snippetID: 2, server: a, at: now)
        now += 10; usage.recordCopy(snippetID: 2, server: a, at: now)
        now += 10; usage.recordCopy(snippetID: 3, server: a, at: now)
        XCTAssertEqual(usage.count(snippetID: 2, server: a), 2)
        XCTAssertEqual(usage.mostUsed(server: a, limit: 10), [2, 3, 1], "3 beats 1 on recency")
        XCTAssertEqual(usage.mostUsed(server: a, limit: 1), [2])
    }

    func testServersAreSeparateAndForgettingWorks() {
        let usage = tracker()
        usage.recordCopy(snippetID: 1, server: a)
        usage.recordCopy(snippetID: 1, server: b)
        usage.recordCopy(snippetID: 1, server: b)
        XCTAssertEqual(usage.count(snippetID: 1, server: a), 1)
        XCTAssertEqual(usage.count(snippetID: 1, server: b), 2)
        usage.forget(snippetID: 1, server: b)
        XCTAssertEqual(usage.mostUsed(server: b, limit: 5), [])
        XCTAssertEqual(usage.mostUsed(server: a, limit: 5), [1])
    }
}
