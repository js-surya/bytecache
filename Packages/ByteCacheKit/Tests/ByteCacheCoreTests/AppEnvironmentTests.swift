import XCTest
@testable import ByteCacheCore

final class AppEnvironmentTests: XCTestCase {
    func testSharedDefaultsFallsBackWithoutAppGroup() {
        XCTAssertNil(AppEnvironment.appGroupID)
        XCTAssertTrue(AppEnvironment.sharedDefaults === UserDefaults.standard)
    }
}
