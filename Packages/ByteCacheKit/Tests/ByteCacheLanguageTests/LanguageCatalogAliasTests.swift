import XCTest
@testable import ByteCacheLanguage

/// CP-77: ByteStash's alternative names for X3 4GL map to its id.
final class LanguageCatalogAliasTests: XCTestCase {
    func testX3AliasesFromByteStash() {
        for alias in ["x3", "x3src", "sage-x3", "4gl", "X3-4GL"] {
            XCTAssertEqual(LanguageCatalog.id(forAlias: alias), "x3", alias)
        }
        XCTAssertEqual(LanguageCatalog.displayName("x3"), "X3 4GL")
    }
}
