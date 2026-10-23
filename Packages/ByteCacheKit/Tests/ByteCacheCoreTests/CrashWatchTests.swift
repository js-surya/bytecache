import XCTest
@testable import ByteCacheCore

/// Noticing that the last session ended unexpectedly (a crash or a freeze the system ended).
final class CrashWatchTests: XCTestCase {
    private func directory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testFirstLaunchIsClean() {
        let watch = CrashWatch(directory: directory())
        watch.launched()
        XCTAssertFalse(watch.endedUnexpectedly)
        XCTAssertNil(watch.unreportedCrash)
    }

    /// A crash waits in Settings → Report a Bug, across launches, until it's reported or dismissed.
    func testAnUnreportedCrashIsKeptUntilReportedOrDismissed() {
        let dir = directory()
        CrashWatch(directory: dir).launched()          // the process dies while open
        let next = CrashWatch(directory: dir)
        next.launched()
        XCTAssertTrue(next.endedUnexpectedly)
        XCTAssertNotNil(next.unreportedCrash)
        next.enteredBackground()                       // a normal end…

        let later = CrashWatch(directory: dir)
        later.launched()
        XCTAssertFalse(later.endedUnexpectedly, "this launch is fine…")
        XCTAssertEqual(later.unreportedCrash, next.unreportedCrash, "…but the earlier crash still waits")
        later.clearUnreportedCrash()
        XCTAssertNil(later.unreportedCrash)
        later.enteredBackground()

        let after = CrashWatch(directory: dir)
        after.launched()
        XCTAssertNil(after.unreportedCrash)
    }

    func testEndingWhileInTheForegroundIsUnexpected() {
        let dir = directory()
        CrashWatch(directory: dir).launched()          // ... and the process dies while open
        let next = CrashWatch(directory: dir)
        next.launched()
        XCTAssertTrue(next.endedUnexpectedly)
    }

    func testQuittingOrBeingClosedInTheBackgroundIsNormal() {
        let dir = directory()
        let first = CrashWatch(directory: dir)
        first.launched()
        first.enteredBackground()                       // swiped away or ended by iOS later: fine
        let second = CrashWatch(directory: dir)
        second.launched()
        XCTAssertFalse(second.endedUnexpectedly)
        second.enteredForeground()
        second.terminated()                             // Mac: Quit
        let third = CrashWatch(directory: dir)
        third.launched()
        XCTAssertFalse(third.endedUnexpectedly)
    }

    func testDiagnosticsKeepTheNewestFew() throws {
        let watch = CrashWatch(directory: directory(), keepDiagnostics: 2)
        for n in 1...3 {
            watch.saveDiagnostic(summary: "crash \(n)", json: Data("{\"n\":\(n)}".utf8), date: Date(timeIntervalSince1970: Double(n)))
        }
        let latest = try XCTUnwrap(watch.latestDiagnostic())
        XCTAssertEqual(latest.summary, "crash 3")
        XCTAssertEqual(String(decoding: latest.json, as: UTF8.self), "{\"n\":3}")
        XCTAssertEqual(watch.diagnosticCount, 2)
    }
}
