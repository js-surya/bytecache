import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

/// CP-25: What's New reads the running version's notes from its GitHub release.
final class UpdateCheckerTests: XCTestCase {
    static let releaseJSON = #"""
    {"tag_name":"v1.2.0","name":"ByteCache 1.2.0","html_url":"https://github.com/js-surya/bytecache/releases/tag/v1.2.0",
     "draft":false,"prerelease":false,"published_at":"2026-10-20T10:00:00Z","body":"## What's changed\n- Placeholders",
     "assets":[{"name":"ByteCache-1.2.0-iOS.ipa","browser_download_url":"https://github.com/js-surya/bytecache/releases/download/v1.2.0/ByteCache-1.2.0-iOS.ipa"},
               {"name":"ByteCache-1.2.0-macOS.zip","browser_download_url":"https://github.com/js-surya/bytecache/releases/download/v1.2.0/ByteCache-1.2.0-macOS.zip"},
               {"name":"SHA256SUMS.txt","browser_download_url":"https://example.invalid/sums"}]}
    """#

    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    func testVersionsCompareNumerically() {
        XCTAssertTrue(AppVersion("1.10.0")! > AppVersion("1.9.0")!)
        XCTAssertTrue(AppVersion("v1.2.0")! > AppVersion("1.1")!)
        XCTAssertEqual(AppVersion("1.1"), AppVersion("1.1.0"))
        XCTAssertEqual(AppVersion("v1.1.0 (12)")?.description, "1.1.0")
        XCTAssertNil(AppVersion("latest"))
    }

    func testReadsTheRelease() throws {
        let release = try GitHubRelease.decode(Data(Self.releaseJSON.utf8))
        XCTAssertEqual(release.version, AppVersion("1.2.0"))
        XCTAssertEqual(release.notes, "## What's changed\n- Placeholders")
        XCTAssertEqual(release.page.absoluteString, "https://github.com/js-surya/bytecache/releases/tag/v1.2.0")
    }

    func testWhatsNewShowsOnceAfterAnUpdateButNotOnFirstInstall() {
        let d = defaults()
        XCTAssertFalse(UpdateChecker(current: AppVersion("1.1.0")!, defaults: d).takeWhatsNew(), "first install: nothing to announce")
        XCTAssertFalse(UpdateChecker(current: AppVersion("1.1.0")!, defaults: d).takeWhatsNew(), "same version again")
        XCTAssertTrue(UpdateChecker(current: AppVersion("1.2.0")!, defaults: d).takeWhatsNew(), "updated")
        XCTAssertFalse(UpdateChecker(current: AppVersion("1.2.0")!, defaults: d).takeWhatsNew(), "only once")
    }
}
