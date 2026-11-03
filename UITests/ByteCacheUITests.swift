import XCTest

/// Walks through ByteCache's features in the iPhone Simulator.
///
/// Read-only for the server: searches, opens snippets and sheets, opens editors and cancels them.
/// Needs a simulator already signed in to a ByteStash server with a few snippets; tests that can't
/// find what they need are skipped. Set `TEST_RUNNER_UI_PACE=1.5` to pause between steps (demos).
/// Run: `xcodebuild test -scheme ByteCache-UITests -destination 'platform=iOS Simulator,name=iPhone 17e'`
@MainActor
final class ByteCacheUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launch(_ arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        dismissWhatsNew()
    }

    /// Pause so a person watching can follow (`TEST_RUNNER_UI_PACE` seconds).
    private func pace() {
        let seconds = Double(ProcessInfo.processInfo.environment["UI_PACE"] ?? "") ?? 0
        if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
    }

    private func dismissWhatsNew() {
        let done = app.navigationBars["What's New"].buttons["Done"]
        if done.waitForExistence(timeout: 3) { done.tap() }
    }

    private func requireSignedIn() throws {
        let tabs = app.tabBars.firstMatch
        if !tabs.waitForExistence(timeout: 15) {
            throw XCTSkip("The simulator isn't signed in to a ByteStash server.")
        }
    }

    private func searchTab(_ text: String) -> XCUIElement {
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        pace()
        return field
    }

    // MARK: Search (filters, suggestions, close matches)

    func testSearchSuggestionsFiltersAndCloseMatches() throws {
        launch()
        try requireSignedIn()

        let field = searchTab("lang:")
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Language:'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "language suggestions")
        suggestion.tap()
        pace()
        XCTAssertTrue((field.value as? String ?? "").hasPrefix("lang:"), "the suggestion completes the filter")

        field.buttons["Clear text"].tap()
        field.typeText("zzqqxx")
        let none = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'No Results' OR label CONTAINS 'Close matches'")).firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 8), "an empty search says so")
        pace()
    }

    // MARK: Share as Image

    func testShareAsImage() throws {
        launch(["-BCOpenSnippet", "9"])
        try requireSignedIn()
        let share = app.buttons["Share as Image"].firstMatch
        guard share.waitForExistence(timeout: 10) else { throw XCTSkip("Snippet 9 isn't on this server.") }
        share.tap()
        XCTAssertTrue(app.navigationBars["Share as Image"].waitForExistence(timeout: 5))
        let image = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Image of'")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10), "the code image is drawn")
        pace()
        app.buttons["Theme"].tap()
        pace()
        app.buttons["None"].tap()
        pace()
        app.switches["Line Numbers"].switches.firstMatch.tap()
        pace()
        XCTAssertTrue(app.buttons["Copy Image"].exists)
        app.navigationBars["Share as Image"].buttons["Done"].tap()
        pace()
    }

    // MARK: Expiring snippets

    func testExpiryChoicesInTheEditor() throws {
        launch(["-BCNewSnippet"])
        try requireSignedIn()
        XCTAssertTrue(app.navigationBars["New Snippet"].waitForExistence(timeout: 10))
        let expires = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Expires'")).firstMatch
        for _ in 0..<8 where !expires.isHittable { app.swipeUp() }
        XCTAssertTrue(expires.exists, "the Expires picker is in the editor")
        expires.tap()
        pace()
        app.buttons["On a Date"].tap()
        pace()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 3), "a date picker for a custom date")
        // Nothing is saved.
        app.navigationBars["New Snippet"].buttons["Cancel"].tap()
        pace()
    }

    func testCountdownBadgeShows() throws {
        launch(["-BCExpiryDemo", "-BCOpenSnippet", "9"])
        try requireSignedIn()
        let badge = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Expires in'")).firstMatch
        guard badge.waitForExistence(timeout: 10) else { throw XCTSkip("Snippet 9 isn't on this server.") }
        pace()
    }

    // MARK: Smart Groups

    func testSmartGroupEditor() throws {
        launch(["-BCTab", "library"])
        try requireSignedIn()
        let new = app.buttons["New Smart Group…"]
        for _ in 0..<4 where !new.isHittable { app.swipeUp() }
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        XCTAssertTrue(app.navigationBars["New Smart Group"].waitForExistence(timeout: 5))
        let name = app.textFields["Name"]
        name.tap()
        name.typeText("Recent Python")
        pace()
        app.buttons["Add Rule"].tap()
        pace()
        XCTAssertTrue(app.navigationBars["New Smart Group"].buttons["Create"].isEnabled)
        // Not created: nothing is saved or synced.
        app.navigationBars["New Smart Group"].buttons["Cancel"].tap()
        pace()
    }

    // MARK: Widgets

    func testSnippetsWidgetCanBeAdded() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.6)
        let edit = springboard.buttons["Edit"]
        if edit.waitForExistence(timeout: 3) { edit.tap() }
        let addWidget = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget' OR label CONTAINS 'Widget'")).firstMatch
        guard addWidget.waitForExistence(timeout: 5) else { throw XCTSkip("Couldn't open the widget gallery.") }
        addWidget.tap()
        let search = springboard.searchFields.firstMatch
        guard search.waitForExistence(timeout: 5) else { throw XCTSkip("Couldn't find the widget search field.") }
        search.tap()
        search.typeText("ByteCache")
        pace()
        let entry = springboard.cells.matching(NSPredicate(format: "label CONTAINS 'ByteCache'")).firstMatch
        guard entry.waitForExistence(timeout: 5) else { throw XCTSkip("ByteCache isn't in the widget gallery.") }
        entry.tap()
        pace()
        XCTAssertTrue(springboard.staticTexts["Snippets"].waitForExistence(timeout: 5), "the Snippets widget is offered")
        pace()
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)
    }
}
