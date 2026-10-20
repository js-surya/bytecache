import XCTest
@testable import ByteCacheCore

/// CP-47: Smart Groups.
final class SmartGroupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snippet(_ title: String, language: String = "python", tags: [String] = [], pinned: Bool = false,
                         favorite: Bool = false, code: String = "", daysAgo: Double = 1) -> Snippet {
        Snippet(id: 1, title: title, description: "about \(title)", updatedAt: now.addingTimeInterval(-daysAgo * 86_400),
                expiryDate: nil, isPublic: false, isPinned: pinned, isFavorite: favorite, categories: tags,
                fragments: [Fragment(id: 1, fileName: "f", code: code, language: language, position: 0)], shareCount: 0)
    }

    func testRules() {
        let s = snippet("CSV Reader", tags: ["IO"], pinned: true, code: "import csv", daysAgo: 3)
        XCTAssertTrue(SmartRule(field: .title, value: "csv").matches(s, now: now))
        XCTAssertFalse(SmartRule(field: .title, negated: true, value: "csv").matches(s, now: now))
        XCTAssertTrue(SmartRule(field: .description, value: "ABOUT").matches(s, now: now))
        XCTAssertTrue(SmartRule(field: .code, value: "import").matches(s, now: now))
        XCTAssertTrue(SmartRule(field: .language, value: "Python").matches(s, now: now))
        XCTAssertTrue(SmartRule(field: .tag, value: "io").matches(s, now: now))
        XCTAssertTrue(SmartRule(field: .tag, negated: true, value: "web").matches(s, now: now))
        XCTAssertTrue(SmartRule(field: .pinned).matches(s, now: now))
        XCTAssertFalse(SmartRule(field: .favorite).matches(s, now: now))
        XCTAssertTrue(SmartRule(field: .modifiedWithinDays, value: "7").matches(s, now: now))
        XCTAssertFalse(SmartRule(field: .modifiedWithinDays, value: "2").matches(s, now: now))
    }

    func testMatchAllAnyNone() {
        let s = snippet("CSV Reader", language: "python", favorite: true)
        let rules = [SmartRule(field: .language, value: "python"), SmartRule(field: .pinned)]
        XCTAssertFalse(SmartGroup(name: "g", match: .all, rules: rules).matches(s, now: now))
        XCTAssertTrue(SmartGroup(name: "g", match: .any, rules: rules).matches(s, now: now))
        XCTAssertFalse(SmartGroup(name: "g", match: .none, rules: rules).matches(s, now: now))
        XCTAssertTrue(SmartGroup(name: "Everything").matches(s, now: now))
    }

    func testRoundTripsThroughJSON() throws {
        let group = SmartGroup(name: "Recent Python", match: .any,
                               rules: [SmartRule(field: .language, value: "python"), SmartRule(field: .modifiedWithinDays, value: "30")])
        XCTAssertEqual(try JSONDecoder().decode(SmartGroup.self, from: JSONEncoder().encode(group)), group)
    }
}
