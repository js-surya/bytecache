import XCTest
@testable import ByteCacheFeatures
#if canImport(AppKit)
import AppKit
#endif

final class IconTests: XCTestCase {
    /// Every icon is a real SF Symbol on this system (a typo would show nothing).
    func testEverySymbolExists() {
        XCTAssertGreaterThan(AppSymbol.allCases.count, 50)
        for symbol in AppSymbol.allCases {
            #if canImport(AppKit)
            XCTAssertNotNil(NSImage(systemSymbolName: symbol.sfName, accessibilityDescription: nil), "SF Symbol \(symbol.sfName)")
            #endif
        }
    }

    /// Versions before 1.3 synced an icon style (SF Symbols or Lucide); it's ignored now.
    func testSettingsSyncedByOlderVersionsStillDecode() throws {
        let old = #"{"appearance":"dark","accent":"blue","codeThemeID":"xcode","codeFontSize":14,"showLineNumbers":true,"iconStyle":"lucide"}"#
        let decoded = try JSONDecoder().decode(SyncedSettings.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.appearance, .dark)
    }
}

/// Lucide was an icon style until 1.3; Acknowledgements keeps crediting it.
final class LucideLicenceTests: XCTestCase {
    func testFullLicenceShipsWithTheApp() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "LUCIDE-LICENSE", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("ISC License"))
        XCTAssertTrue(text.contains("Cole Bemis"))
    }
}
