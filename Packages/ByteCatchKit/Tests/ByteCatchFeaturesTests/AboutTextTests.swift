import XCTest
@testable import ByteCatchFeatures

final class AboutTextTests: XCTestCase {
    func testTaglineMarksClientAsUnofficial() {
        XCTAssertTrue(AboutText.tagline.localizedCaseInsensitiveContains("unofficial"))
    }
}
