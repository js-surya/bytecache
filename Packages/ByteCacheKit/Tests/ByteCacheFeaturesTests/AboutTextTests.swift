import XCTest
@testable import ByteCacheFeatures

/// CP-13: credits and the developer's GitHub link.
final class AboutTextTests: XCTestCase {
    /// CP-18: renamed to ByteCache with the tagline "Cache the bytes".
    func testNameAndTagline() {
        XCTAssertEqual(AboutText.appName, "ByteCache")
        XCTAssertEqual(AboutText.tagline, "Cache the bytes")
    }

    func testCreditsAndGitHubLink() {
        XCTAssertEqual(AboutText.credit, "Built with ❤️ by SyntaxError and Claude")
        XCTAssertEqual(AboutText.developerGitHub.absoluteString, "https://github.com/js-surya")
    }
}
