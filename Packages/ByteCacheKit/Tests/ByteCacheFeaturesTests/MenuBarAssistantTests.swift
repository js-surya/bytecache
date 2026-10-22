import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// CP-69: the menu bar assistant's settings and what the list shows when it opens.
@MainActor
final class MenuBarAssistantTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "bytecache.menubar.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testDefaults() {
        let s = AppSettings(defaults: defaults())
        XCTAssertEqual(s.quickSearchStart, .recent)
        XCTAssertTrue(s.quickSearchClearsOnOpen)
        XCTAssertEqual(s.menuBarPanelSize, .medium)
        XCTAssertFalse(s.menuBarOnly)
    }

    func testStartListRoundTripsIncludingSmartGroups() {
        let id = UUID()
        for start in [QuickSearchStart.recent, .pinned, .favorites, .smartGroup(id)] {
            XCTAssertEqual(QuickSearchStart(rawValue: start.rawValue), start)
        }
        XCTAssertNil(QuickSearchStart(rawValue: "group:not-a-uuid"))
        XCTAssertEqual(QuickSearchStart.smartGroup(id).sidebarItem, .smartGroup(id))
        XCTAssertEqual(QuickSearchStart.pinned.sidebarItem, .pinned)
        XCTAssertEqual(QuickSearchStart.recent.sidebarItem, .all)
    }

    func testSettingsAreRemembered() {
        let d = defaults()
        let first = AppSettings(defaults: d)
        first.quickSearchStart = .favorites
        first.quickSearchClearsOnOpen = false
        first.menuBarPanelSize = .large
        first.menuBarOnly = true
        let again = AppSettings(defaults: d)
        XCTAssertEqual(again.quickSearchStart, .favorites)
        XCTAssertFalse(again.quickSearchClearsOnOpen)
        XCTAssertEqual(again.menuBarPanelSize, .large)
        XCTAssertTrue(again.menuBarOnly)
    }

    func testMenuBarOnlyKeepsTheMenuBarIcon() {
        let s = AppSettings(defaults: defaults())
        s.quickSearchInMenuBar = false
        s.menuBarOnly = true
        XCTAssertTrue(s.quickSearchInMenuBar, "without a Dock icon the menu bar icon is the way back in")
    }

    func testOpeningShowsTheStartListAndClearsTheSearch() async {
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.page([])), .json(TestJSON.page([]))])
        let model = QuickSearchModel(list: SnippetListModel(session: session, cache: nil))
        model.list.searchText = "old"
        await model.opened(start: .pinned, clearSearch: true)
        XCTAssertEqual(model.list.searchText, "")
        XCTAssertEqual(model.list.selection, .pinned)
        XCTAssertEqual(transport.last.url?.query?.contains("pinned=true"), true)

        model.list.searchText = "keep"
        await model.opened(start: .pinned, clearSearch: false)
        XCTAssertEqual(model.list.searchText, "keep")
        XCTAssertEqual(model.list.selection, .all, "a search looks in every snippet, not just the start list")
    }
}
