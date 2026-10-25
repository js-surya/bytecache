import XCTest
@testable import ByteCacheFeatures
import ByteCacheCore

/// CP-82: each Mac window gets its own toolbar id, so AppKit doesn't sync toolbars whose items differ.
@MainActor
final class WindowToolbarIDTests: XCTestCase {
    #if os(macOS)
    func testFirstWindowKeepsPlainIDOthersAreNumbered() {
        let first = WindowToolbarID(base: "test-a")
        let second = WindowToolbarID(base: "test-a")
        let third = WindowToolbarID(base: "test-a")
        XCTAssertEqual([first.id, second.id, third.id], ["test-a", "test-a-2", "test-a-3"])
    }

    func testClosedWindowsNumberIsReused() {
        let first = WindowToolbarID(base: "test-b")
        var second: WindowToolbarID? = WindowToolbarID(base: "test-b")
        XCTAssertEqual(second?.id, "test-b-2")
        second = nil
        XCTAssertEqual(WindowToolbarID.count(base: "test-b"), 1)
        XCTAssertEqual(WindowToolbarID(base: "test-b").id, "test-b-2")
        XCTAssertEqual(first.id, "test-b")
    }

    func testBasesAreIndependent() {
        let main = WindowToolbarID(base: "test-c")
        let snippet = WindowToolbarID(base: "test-d")
        XCTAssertEqual([main.id, snippet.id], ["test-c", "test-d"])
    }
    #endif
}

/// CP-91: the backup key's name says which device made it.
@MainActor
final class BackupKeyNameTests: XCTestCase {
    func testNameHasPlatformModelAndADate() {
        let device = DeviceInfo.current
        let name = SessionManager.backupKeyName(on: Date(timeIntervalSince1970: 1_792_800_000))
        XCTAssertTrue(name.hasPrefix("ByteCache on \(device.platform) (\(device.model)), "), name)
        XCTAssertTrue(name.range(of: #", \d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil, name)
    }
}
