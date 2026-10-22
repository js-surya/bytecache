import XCTest
@testable import ByteCacheFeatures

/// CP-68: what Return, ⌥Return and ⌘Return do in Quick Search and the menu bar.
@MainActor
final class QuickSearchActionTests: XCTestCase {
    private func settings() -> AppSettings {
        let name = "bytecache.quickaction.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return AppSettings(defaults: defaults)
    }

    func testReturnCopiesAndOptionReturnPastesByDefault() {
        let s = settings()
        XCTAssertEqual(s.quickSearchReturnAction, .copy)
        XCTAssertEqual(s.quickSearchOptionReturnAction, .paste)
    }

    func testKeysPickTheirAction() {
        let s = settings()
        s.quickSearchReturnAction = .paste
        s.quickSearchOptionReturnAction = .copy
        XCTAssertEqual(QuickSearchAction.forReturn(option: false, command: false, settings: s), .paste)
        XCTAssertEqual(QuickSearchAction.forReturn(option: true, command: false, settings: s), .copy)
        XCTAssertEqual(QuickSearchAction.forReturn(option: false, command: true, settings: s), .open, "⌘Return always opens")
        XCTAssertEqual(QuickSearchAction.forReturn(option: true, command: true, settings: s), .open)
    }

    func testChoicesAreRemembered() {
        let name = "bytecache.quickaction.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = AppSettings(defaults: defaults)
        first.quickSearchReturnAction = .open
        first.quickSearchOptionReturnAction = .copy
        let again = AppSettings(defaults: defaults)
        XCTAssertEqual(again.quickSearchReturnAction, .open)
        XCTAssertEqual(again.quickSearchOptionReturnAction, .copy)
    }

    func testHintDescribesTheChosenActions() {
        let s = settings()
        XCTAssertEqual(QuickSearchAction.hint(settings: s), "Return copies · ⌥Return pastes · ⌘Return opens · Esc closes")
        s.quickSearchReturnAction = .paste
        s.quickSearchOptionReturnAction = .paste
        XCTAssertEqual(QuickSearchAction.hint(settings: s), "Return pastes · ⌘Return opens · Esc closes",
                       "⌥Return isn't mentioned when it does the same as Return")
    }
}
