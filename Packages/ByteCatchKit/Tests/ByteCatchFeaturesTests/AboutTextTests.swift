import XCTest
@testable import ByteCatchFeatures

/// CP-13: credits and the developer's GitHub link.
final class AboutTextTests: XCTestCase {
    func testCreditsAndGitHubLink() {
        XCTAssertEqual(AboutText.credit, "Built with ❤️ by SyntaxError and Claude")
        XCTAssertEqual(AboutText.developerGitHub.absoluteString, "https://github.com/js-surya")
    }
}
