import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// CP-25: What's New once after an update.
@MainActor
final class UpdateModelTests: XCTestCase {
    private let release = #"{"tag_name":"v1.2.0","name":"ByteCache 1.2.0","html_url":"https://github.com/js-surya/bytecache/releases/tag/v1.2.0","draft":false,"prerelease":false,"body":"Notes","assets":[]}"#

    func testWhatsNewAfterUpdatingShowsTheRunningVersionsNotes() async {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        _ = UpdateChecker(current: AppVersion("1.1.0")!, defaults: d).takeWhatsNew() // was running 1.1.0
        let transport = StubTransport([.json(release)])
        let model = UpdateModel(checker: UpdateChecker(current: AppVersion("1.2.0")!, defaults: d, transport: transport))
        await model.appBecameActive()
        XCTAssertEqual(model.whatsNew?.version, AppVersion("1.2.0"))
        XCTAssertTrue(transport.requests.first?.url?.path().hasSuffix("/releases/tags/v1.2.0") == true)
        XCTAssertEqual(transport.requests.count, 1, "no other GitHub requests: updates come through TestFlight and the App Store")
    }

    func testNothingIsFetchedWithoutAnUpdate() async {
        let transport = StubTransport([])
        let model = UpdateModel(checker: UpdateChecker(current: AppVersion("1.2.0")!, defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                                       transport: transport))
        await model.appBecameActive()
        XCTAssertNil(model.whatsNew)
        XCTAssertTrue(transport.requests.isEmpty)
    }
}

/// Release notes as shown in What's New: no Install section (the app is already installed),
/// no tables (the Markdown view doesn't draw them) and no commit-type prefixes.
final class ReleaseNotesTests: XCTestCase {
    func testCleansReleaseNotesForTheSheet() {
        let notes = """
        ## Install
        | Device | File | How |
        |---|---|---|
        | iPhone and iPad | `a.ipa` | Sideload |

        Requires iOS 17.

        ## What's changed
        - fix(ui): Settings button top-left (CP-21)
        - feat(support): Report a Bug (CP-14)
        - fix(scan): fall back to fast recognition (CP-20)
        - iPad sidebar toggle uses the accent colour (CP-22)

        | Other | Table |
        |---|---|
        | x | y |
        """
        XCTAssertEqual(ReleaseNotes.forDisplay(notes), """
        ## What's changed
        - Settings button top-left (CP-21)
        - Report a Bug (CP-14)
        - Fall back to fast recognition (CP-20)
        - iPad sidebar toggle uses the accent colour (CP-22)

        - Other · Table
        - x · y
        """)
    }
}
