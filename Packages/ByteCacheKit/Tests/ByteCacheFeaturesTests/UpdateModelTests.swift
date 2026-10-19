import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// CP-25: when to show the update and What's New sheets.
@MainActor
final class UpdateModelTests: XCTestCase {
    private let release = #"{"tag_name":"v1.2.0","name":"ByteCache 1.2.0","html_url":"https://github.com/js-surya/bytecache/releases/tag/v1.2.0","draft":false,"prerelease":false,"body":"Notes","assets":[]}"#

    private func make(version: String, replies: [StubTransport.Reply], defaults: UserDefaults? = nil,
                      checkOn: Bool = true) -> (UpdateModel, StubTransport, AppSettings) {
        let d = defaults ?? UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: d)
        settings.checkForUpdates = checkOn
        let transport = StubTransport(replies)
        let model = UpdateModel(settings: settings, checker: UpdateChecker(current: AppVersion(version)!, defaults: d, transport: transport))
        return (model, transport, settings)
    }

    func testNewerReleaseIsOfferedAndCanBeSkipped() async {
        let (model, _, _) = make(version: "1.1.0", replies: [.json(release)])
        await model.appBecameActive()
        XCTAssertEqual(model.offered?.version, AppVersion("1.2.0"))
        model.skipOffered()
        XCTAssertNil(model.offered)
    }

    func testSwitchedOffMeansNoAutomaticCheck() async {
        let (model, transport, _) = make(version: "1.1.0", replies: [.json(release)], checkOn: false)
        await model.appBecameActive()
        XCTAssertNil(model.offered)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testCheckNowReportsUpToDate() async {
        let (model, _, _) = make(version: "1.2.0", replies: [.json(release)])
        await model.checkNow()
        XCTAssertNil(model.offered)
        XCTAssertEqual(model.status, "ByteCache 1.2.0 is the latest version.")
    }

    func testWhatsNewAfterUpdatingShowsTheRunningVersionsNotes() async {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        _ = UpdateChecker(current: AppVersion("1.1.0")!, defaults: d).takeWhatsNew() // was running 1.1.0
        let current = release
        let (model, transport, _) = make(version: "1.2.0", replies: [.json(current), .json(release)], defaults: d)
        await model.appBecameActive()
        XCTAssertEqual(model.whatsNew?.version, AppVersion("1.2.0"))
        XCTAssertTrue(transport.requests.first?.url?.path().hasSuffix("/releases/tags/v1.2.0") == true)
        XCTAssertNil(model.offered, "already on the latest")
    }
}

/// Release notes as shown in the app: no install table (the sheet has its own Download button),
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
