import XCTest
import ByteCacheCore
@testable import ByteCacheFeatures

/// The app details sent with a bug report: settings and state, nothing personal.
final class ReportContextTests: XCTestCase {
    private func inputs() -> ReportContext.Inputs {
        ReportContext.Inputs(
            install: .appStore, language: "en-IN", appearance: "Dark",
            languageIcons: "Colour", appIcon: "Default", iCloudSync: true, handoff: false,
            appLock: true, widgetsWhileLocked: "Titles Only", servers: 2, signIn: "API key",
            network: "Wi-Fi", lowPower: false, widgets: "App Group", lastProblem: nil)
    }

    func testDescribesTheAppWithoutAnythingPersonal() {
        let lines = ReportContext(inputs()).lines
        XCTAssertEqual(lines, [
            "Installed from: App Store or TestFlight",
            "Language: en-IN",
            "Look: Dark · Colour language icons · Default app icon",
            "iCloud Sync: on · Handoff: off · App Lock: on (widgets: Titles Only)",
            "Servers: 2 · Signed in with: API key",
            "Network: Wi-Fi · Low Power Mode: off",
            "Widgets: App Group",
        ])
    }

    func testOptionalDetailsAppearOnlyWhenKnown() {
        var i = inputs()
        i.appLock = false
        i.network = nil
        i.widgets = nil
        i.install = .direct
        i.lastProblem = "crash on 2026-10-21 (EXC_BAD_ACCESS)"
        let lines = ReportContext(i).lines
        XCTAssertTrue(lines.contains("Installed from: GitHub or Xcode"))
        XCTAssertTrue(lines.contains("iCloud Sync: on · Handoff: off · App Lock: off"))
        XCTAssertTrue(lines.contains("Low Power Mode: off"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("Widgets") })
        XCTAssertEqual(lines.last, "Last problem: crash on 2026-10-21 (EXC_BAD_ACCESS)")
    }
}
