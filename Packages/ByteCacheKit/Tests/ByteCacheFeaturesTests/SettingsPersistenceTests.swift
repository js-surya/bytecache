import XCTest
@testable import ByteCacheFeatures

/// CP-12: every setting survives an app restart.
@MainActor
final class SettingsPersistenceTests: XCTestCase {
    func testEverySettingIsRemembered() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = AppSettings(defaults: defaults)
        first.appearance = .dark
        first.accent = .orange
        first.codeThemeID = "dracula"
        first.iconStyle = .lucide
        first.searchInCode = true
        first.showLineNumbers = false
        first.wrapLines = true
        first.codeFontSize = 18
        first.iCloudSyncEnabled = false
        first.handoffEnabled = false
        first.suggestionsEnabled = false
        first.hapticsEnabled = false
        first.hapticStrength = .strong
        first.languageIconStyle = .monochrome
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.appearance, .dark)
        XCTAssertEqual(second.accent, .orange)
        XCTAssertEqual(second.codeThemeID, "dracula")
        XCTAssertEqual(second.iconStyle, .lucide)
        XCTAssertTrue(second.searchInCode)
        XCTAssertFalse(second.showLineNumbers)
        XCTAssertTrue(second.wrapLines)
        XCTAssertEqual(second.codeFontSize, 18)
        XCTAssertFalse(second.iCloudSyncEnabled)
        XCTAssertFalse(second.handoffEnabled)
        XCTAssertFalse(second.suggestionsEnabled)
        XCTAssertFalse(second.hapticsEnabled)
        XCTAssertEqual(second.hapticStrength, .strong)
        XCTAssertEqual(second.languageIconStyle, .monochrome)
        XCTAssertEqual(AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!).languageIconStyle, .color, "colour by default")
    }

    func testSettingsSectionsHaveHeaders() {
        XCTAssertEqual(SettingsSection.allCases.map(\.title),
                       ["Account", "Look & Feel", "Snippets", "Privacy & Security", "Sync & Backup", "Support"])
    }
}
