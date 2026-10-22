import XCTest
@testable import ByteCacheFeatures

/// CP-63: signed builds keep iCloud; only the unsigned GitHub build (UNSIGNED_BUILD) drops it.
@MainActor
final class BuildFeaturesTests: XCTestCase {
    func testSignedBuildsHaveICloud() {
        #if UNSIGNED_BUILD
        XCTAssertFalse(BuildFeatures.iCloud)
        #else
        XCTAssertTrue(BuildFeatures.iCloud)
        #endif
    }

}
