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
        XCTAssertEqual(AboutText.credit, "Made with ❤️ by SyntaxError")
        XCTAssertEqual(AboutText.sourceCode.absoluteString, "https://github.com/js-surya/bytecache", "links to the project, not a profile")
    }

    /// CP-26: people see "1.1.0"; bug reports keep the build number ("1.1.0 (12)").
    func testDisplayedVersionHasNoBuildNumber() {
        XCTAssertFalse(AboutText.displayVersion.contains("("), AboutText.displayVersion)
        XCTAssertTrue(AboutText.versionWithBuild.hasPrefix(AboutText.displayVersion + " ("), AboutText.versionWithBuild)
    }

    #if TIP_LINKS
    func testSupportLinkGoesToKofi() {
        XCTAssertEqual(AboutText.support.absoluteString, "https://ko-fi.com/trailingfox")
    }
    #endif
}
