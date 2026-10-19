import XCTest
@testable import ByteCatchFeatures
#if canImport(AppKit)
import AppKit
#endif

final class IconTests: XCTestCase {
    func testEverySymbolExistsInBothStyles() {
        XCTAssertGreaterThan(AppSymbol.allCases.count, 50)
        for symbol in AppSymbol.allCases {
            #if canImport(AppKit)
            XCTAssertNotNil(NSImage(systemSymbolName: symbol.sfName, accessibilityDescription: nil), "SF Symbol \(symbol.sfName)")
            XCTAssertNotNil(Bundle.module.image(forResource: symbol.lucideAsset), "Lucide asset \(symbol.lucideAsset)")
            #endif
        }
    }

    @MainActor
    func testIconStyleIsSyncedAndDefaultsToSFSymbols() {
        let name = "bytecatch.icons.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.iconStyle, .sfSymbols)
        settings.iconStyle = .lucide
        XCTAssertEqual(AppSettings(defaults: defaults).iconStyle, .lucide)
        XCTAssertEqual(settings.synced.iconStyle, .lucide)
    }

    func testOlderSyncedSettingsWithoutIconStyleStillDecode() throws {
        let old = #"{"appearance":"dark","accent":"blue","codeThemeID":"xcode","codeFontSize":14,"showLineNumbers":true}"#
        let decoded = try JSONDecoder().decode(SyncedSettings.self, from: Data(old.utf8))
        XCTAssertNil(decoded.iconStyle)
    }
}

final class LucideLicenceTests: XCTestCase {
    func testFullLicenceShipsWithTheApp() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "LUCIDE-LICENSE", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("ISC License"))
        XCTAssertTrue(text.contains("Cole Bemis"))
    }
}
