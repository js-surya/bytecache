import XCTest
@testable import ByteCacheCore

/// CP-54: expiring snippets.
final class SnippetExpiryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let one = try! ServerURL("https://one.example.com")
    private let two = try! ServerURL("https://two.example.com")

    func testDueSnippetsPerServer() {
        var expiries = SnippetExpiries()
        expiries.set(now.addingTimeInterval(-10), snippetID: 3, server: one)
        expiries.set(now.addingTimeInterval(60), snippetID: 4, server: one)
        expiries.set(now.addingTimeInterval(-10), snippetID: 5, server: two)
        XCTAssertEqual(expiries.due(server: one, now: now), [3])
        XCTAssertEqual(expiries.due(server: two, now: now), [5])
        XCTAssertEqual(expiries.date(snippetID: 4, server: one), now.addingTimeInterval(60))
        expiries.set(nil, snippetID: 3, server: one)
        XCTAssertEqual(expiries.due(server: one, now: now), [])
    }

    func testCountdownText() {
        XCTAssertEqual(ExpiryText.remaining(until: now.addingTimeInterval(-1), now: now), "Expired")
        XCTAssertEqual(ExpiryText.remaining(until: now.addingTimeInterval(45), now: now), "Expires in 45s")
        XCTAssertEqual(ExpiryText.remaining(until: now.addingTimeInterval(12 * 60 + 5), now: now), "Expires in 12m")
        XCTAssertEqual(ExpiryText.remaining(until: now.addingTimeInterval(3 * 3600 + 12 * 60), now: now), "Expires in 3h 12m")
        XCTAssertEqual(ExpiryText.remaining(until: now.addingTimeInterval(2 * 86_400 + 4 * 3600 + 30), now: now), "Expires in 2d 4h")
        XCTAssertEqual(ExpiryText.remaining(until: now.addingTimeInterval(86_400), now: now), "Expires in 1d")
        XCTAssertTrue(ExpiryText.isSoon(now.addingTimeInterval(600), now: now))
        XCTAssertFalse(ExpiryText.isSoon(now.addingTimeInterval(7200), now: now))
    }

    func testChoices() {
        XCTAssertNil(ExpiryChoice.never.date(from: now))
        XCTAssertEqual(ExpiryChoice.day.date(from: now), now.addingTimeInterval(86_400))
        XCTAssertEqual(ExpiryChoice.date(now).date(from: .distantPast), now)
    }

    func testRoundTripsThroughJSON() throws {
        var expiries = SnippetExpiries()
        expiries.set(now, snippetID: 9, server: one)
        XCTAssertEqual(try JSONDecoder().decode(SnippetExpiries.self, from: JSONEncoder().encode(expiries)), expiries)
    }
}
