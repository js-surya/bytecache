import XCTest
@testable import ByteCacheFeatures

/// CP-71: Back / Forward through the sections and snippets you looked at.
final class NavigationHistoryTests: XCTestCase {
    func testStartsWithNowhereToGo() {
        let h = NavigationHistory(start: .all)
        XCTAssertFalse(h.canGoBack)
        XCTAssertFalse(h.canGoForward)
        XCTAssertEqual(h.current, .init(section: .all, snippet: nil))
    }

    func testOpeningSnippetsAndSectionsCanBeRetraced() {
        var h = NavigationHistory(start: .all)
        h.visit(snippet: 1)
        h.visit(snippet: 2)
        h.visit(section: .pinned)
        h.visit(snippet: 3)
        XCTAssertEqual(h.back(), .init(section: .all, snippet: 2), "picking a snippet fills in the section's empty entry")
        XCTAssertEqual(h.back(), .init(section: .all, snippet: 1))
        XCTAssertNil(h.back())
        XCTAssertEqual(h.forward(), .init(section: .all, snippet: 2))
        XCTAssertEqual(h.forward(), .init(section: .pinned, snippet: 3))
        XCTAssertNil(h.forward())
    }

    func testVisitingAfterGoingBackDropsTheForwardEntries() {
        var h = NavigationHistory(start: .all)
        h.visit(snippet: 1)
        h.visit(snippet: 2)
        _ = h.back()
        h.visit(snippet: 5)
        XCTAssertFalse(h.canGoForward)
        XCTAssertEqual(h.back(), .init(section: .all, snippet: 1))
    }

    func testRestoringAnEntryRecordsNothing() {
        var h = NavigationHistory(start: .all)
        h.visit(snippet: 1)
        h.visit(section: .pinned)
        h.visit(snippet: 3)
        let entry = h.back()!          // (.all, 1): the app now selects .all, then snippet 1
        h.visit(section: entry.section)
        h.visit(snippet: entry.snippet)
        XCTAssertTrue(h.canGoForward)
        XCTAssertEqual(h.current, entry)
    }

    func testDeselectingIsNotAPlace() {
        var h = NavigationHistory(start: .all)
        h.visit(snippet: 1)
        h.visit(snippet: nil)
        XCTAssertFalse(h.canGoBack)
        XCTAssertEqual(h.current.snippet, 1)
    }

    func testKeepsTheLatestHundredEntries() {
        var h = NavigationHistory(start: .all)
        for id in 1...150 { h.visit(snippet: id) }
        var steps = 0
        while h.back() != nil { steps += 1 }
        XCTAssertEqual(steps, 99)
    }
}
