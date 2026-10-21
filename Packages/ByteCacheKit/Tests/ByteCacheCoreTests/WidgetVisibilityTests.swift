import XCTest
@testable import ByteCacheCore

/// What widgets may show while App Lock is on.
final class WidgetVisibilityTests: XCTestCase {
    func testWithoutAppLockWidgetsShowEverything() {
        for mode in WidgetLockMode.allCases {
            XCTAssertEqual(WidgetVisibility.resolve(appLockEnabled: false, mode: mode), .everything)
        }
    }

    func testWithAppLockTheChosenModeApplies() {
        XCTAssertEqual(WidgetVisibility.resolve(appLockEnabled: true, mode: .hideAll), .hidden)
        XCTAssertEqual(WidgetVisibility.resolve(appLockEnabled: true, mode: .titlesOnly), .titlesOnly)
        XCTAssertEqual(WidgetVisibility.resolve(appLockEnabled: true, mode: .showAll), .everything)
    }

    func testTitlesOnlyIsTheDefault() {
        let name = "bytecache.widgetmode.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertEqual(WidgetLockMode.stored(in: d), .titlesOnly)
        d.set(true, forKey: AppEnvironment.appLockEnabledKey)
        XCTAssertEqual(WidgetVisibility.current(in: d), .titlesOnly)
        d.set(WidgetLockMode.hideAll.rawValue, forKey: WidgetLockMode.defaultsKey)
        XCTAssertEqual(WidgetVisibility.current(in: d), .hidden)
    }

    func testOnlyEverythingAllowsCopying() {
        XCTAssertTrue(WidgetVisibility.everything.allowsCopy)
        XCTAssertFalse(WidgetVisibility.titlesOnly.allowsCopy)
        XCTAssertFalse(WidgetVisibility.hidden.allowsCopy)
    }
}
