import XCTest
@testable import ByteCatchCore

final class AppEnvironmentTests: XCTestCase {
    func testSharedDefaultsFallsBackWithoutAppGroup() {
        XCTAssertNil(AppEnvironment.appGroupID)
        XCTAssertTrue(AppEnvironment.sharedDefaults === UserDefaults.standard)
    }
}
