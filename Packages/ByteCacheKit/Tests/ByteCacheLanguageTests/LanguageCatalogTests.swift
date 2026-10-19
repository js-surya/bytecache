import XCTest
@testable import ByteCacheLanguage

final class LanguageCatalogTests: XCTestCase {
    func testCatalogHasUniqueIdsIncludingPlaintext() {
        XCTAssertEqual(Set(LanguageCatalog.ids).count, LanguageCatalog.ids.count)
        XCTAssertEqual(LanguageCatalog.ids.count, 53)
        XCTAssertTrue(LanguageCatalog.ids.contains("plaintext"))
    }
}
