import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

/// CP-25: tell sideloaded users about new releases on GitHub.
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

    func testReadsTheReleaseAndPicksTheDownloadForEachDevice() throws {
        let release = try GitHubRelease.decode(Data(Self.releaseJSON.utf8))
        XCTAssertEqual(release.version, AppVersion("1.2.0"))
        XCTAssertEqual(release.notes, "## What's changed\n- Placeholders")
        XCTAssertEqual(release.download(for: .iOS)?.lastPathComponent, "ByteCache-1.2.0-iOS.ipa")
        XCTAssertEqual(release.download(for: .macOS)?.lastPathComponent, "ByteCache-1.2.0-macOS.zip")
        XCTAssertEqual(release.page.absoluteString, "https://github.com/js-surya/bytecache/releases/tag/v1.2.0")
    }

    func testOffersANewerVersionAndAsksGitHubForTheLatestRelease() async throws {
        let transport = StubTransport([.json(Self.releaseJSON)])
        let checker = UpdateChecker(current: AppVersion("1.1.0")!, defaults: defaults(), transport: transport)
        let result = await checker.check(force: false)
        XCTAssertEqual(result, .available(try GitHubRelease.decode(Data(Self.releaseJSON.utf8))))
        XCTAssertEqual(transport.requests.first?.url?.absoluteString, "https://api.github.com/repos/js-surya/bytecache/releases/latest")
    }

    func testUpToDateWhenTheSameOrOlder() async {
        for current in ["1.2.0", "1.3.0"] {
            let checker = UpdateChecker(current: AppVersion(current)!, defaults: defaults(), transport: StubTransport([.json(Self.releaseJSON)]))
            let result = await checker.check(force: true)
            XCTAssertEqual(result, .upToDate)
        }
    }

    func testAutomaticChecksRunAtMostOnceADay() async {
        let d = defaults()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let transport = StubTransport([.json(Self.releaseJSON), .json(Self.releaseJSON)])
        let checker = UpdateChecker(current: AppVersion("1.1.0")!, defaults: d, transport: transport, now: { now })
        _ = await checker.check(force: false)
        let again = await checker.check(force: false)
        XCTAssertEqual(again, .skippedRecentlyChecked)
        XCTAssertEqual(transport.requests.count, 1)
        now = now.addingTimeInterval(25 * 3600)
        _ = await checker.check(force: false)
        XCTAssertEqual(transport.requests.count, 2, "a day later it checks again")
    }

    func testSkippedVersionIsNotOfferedButANewerOneIs() async throws {
        let d = defaults()
        let checker = UpdateChecker(current: AppVersion("1.1.0")!, defaults: d, transport: StubTransport([.json(Self.releaseJSON)]))
        checker.skip(AppVersion("1.2.0")!)
        let skipped = await checker.check(force: false)
        XCTAssertEqual(skipped, .upToDate)
        let newer = Self.releaseJSON.replacingOccurrences(of: "1.2.0", with: "1.3.0")
        let next = UpdateChecker(current: AppVersion("1.1.0")!, defaults: d, transport: StubTransport([.json(newer)]))
        let result = await next.check(force: true)
        guard case .available(let release) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(release.version, AppVersion("1.3.0"))
    }

    func testOfflineOrRateLimitedFailsQuietly() async {
        let offline = UpdateChecker(current: AppVersion("1.1.0")!, defaults: defaults(),
                                    transport: StubTransport([.failure(URLError(.notConnectedToInternet))]))
        let a = await offline.check(force: true)
        XCTAssertEqual(a, .failed)
        let limited = UpdateChecker(current: AppVersion("1.1.0")!, defaults: defaults(),
                                    transport: StubTransport([.json(#"{"message":"API rate limit exceeded"}"#, status: 403)]))
        let b = await limited.check(force: true)
        XCTAssertEqual(b, .failed)
    }

    func testWhatsNewShowsOnceAfterAnUpdateButNotOnFirstInstall() {
        let d = defaults()
        XCTAssertFalse(UpdateChecker(current: AppVersion("1.1.0")!, defaults: d).takeWhatsNew(), "first install: nothing to announce")
        XCTAssertFalse(UpdateChecker(current: AppVersion("1.1.0")!, defaults: d).takeWhatsNew(), "same version again")
        XCTAssertTrue(UpdateChecker(current: AppVersion("1.2.0")!, defaults: d).takeWhatsNew(), "updated")
        XCTAssertFalse(UpdateChecker(current: AppVersion("1.2.0")!, defaults: d).takeWhatsNew(), "only once")
    }
}
