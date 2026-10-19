import ByteCacheCore
import ByteCacheTestSupport
import XCTest
@testable import ByteCacheFeatures

/// CP-14: report a bug as a pre-filled GitHub issue.
final class BugReportTests: XCTestCase {
    private let device = DeviceInfo(app: "1.1.0 (12)", os: "iOS 26.1", model: "iPhone18,1", platform: "iPhone")

    func testScrubsSecretsEmailsAndServers() {
        let raw = """
        GET https://notes.home.lan/api/snippets → 401 bytestashauth: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOjF9.abcDEF123_-x
        x-api-key: f00dbabe0123456789abcdef0123456789abcdef0123456789abcdef01234567
        login failed for jane.doe@example.com at 192.168.1.20
        """
        let clean = LogScrubber.scrub(raw, serverHosts: ["notes.home.lan"])
        XCTAssertFalse(clean.contains("notes.home.lan"))
        XCTAssertFalse(clean.contains("eyJhbGci"))
        XCTAssertFalse(clean.contains("f00dbabe"))
        XCTAssertFalse(clean.contains("jane.doe"))
        XCTAssertFalse(clean.contains("192.168.1.20"))
        XCTAssertTrue(clean.contains("<server>"))
        XCTAssertTrue(clean.contains("GET https://<server>/api/snippets → 401"), clean)
    }

    func testIssueLinkPrefillsTheBugForm() throws {
        let report = BugReport(title: "Scan crashes", whatHappened: "It crashed & closed", steps: "1. Scan\n2. Boom",
                               device: device, logs: ["2026-10-19T10:00:00Z [scan] failed"])
        let url = report.issueURL()
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/js-surya/bytecache/issues/new?"))
        XCTAssertEqual(items["template"], "bug_report.yml")
        XCTAssertEqual(items["title"], "Scan crashes")
        XCTAssertEqual(items["what"], "It crashed & closed")
        XCTAssertEqual(items["steps"], "1. Scan\n2. Boom")
        XCTAssertEqual(items["versions"], "ByteCache 1.1.0 (12), iOS 26.1, iPhone18,1")
        XCTAssertTrue(items["logs"]?.contains("[scan] failed") == true)
        XCTAssertTrue(report.logsFitInLink)
    }

    func testLongLogsGoToAFileInstead() {
        let logs = (1...800).map { "2026-10-19T10:00:00Z [api] GET /api/snippets/\($0) → 200" }
        let report = BugReport(title: "Slow", whatHappened: "x", steps: "y", device: device, logs: logs)
        XCTAssertFalse(report.logsFitInLink)
        let url = report.issueURL()
        XCTAssertLessThan(url.absoluteString.count, BugReport.maxLinkLength)
        XCTAssertTrue(url.absoluteString.contains("ByteCache-logs.txt"))
        XCTAssertTrue(report.logFileText.contains("/api/snippets/800"))
        XCTAssertTrue(report.logFileText.contains("iOS 26.1"))
    }

    func testEmptyTitleFallsBack() {
        let report = BugReport(title: "  ", whatHappened: "x", steps: "", device: device, logs: [])
        XCTAssertEqual(report.issueTitle, "Bug report")
    }

    @MainActor
    func testModelShowsOnlyScrubbedActivity() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = AppLog(directory: dir)
        log.record("api", "GET https://x.io/api/snippets → 401 for me@x.io")
        let (session, _) = await TestSession.signedIn([])
        let model = ReportBugModel(session: session, log: log, device: device)
        XCTAssertEqual(model.logs.count, 1)
        XCTAssertFalse(model.logs[0].contains("x.io/"))
        XCTAssertFalse(model.logs[0].contains("me@"))
        XCTAssertFalse(model.canSend, "needs a description first")
        model.whatHappened = "It broke"
        XCTAssertTrue(model.canSend)
        model.includeLogs = false
        XCTAssertTrue(model.report.logs.isEmpty)
    }
}
