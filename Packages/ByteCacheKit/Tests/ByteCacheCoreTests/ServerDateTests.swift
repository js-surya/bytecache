import XCTest
@testable import ByteCacheCore

/// Server dates: the fast path gives the same dates as the formatters, in every format ByteStash sends.
final class ServerDateTests: XCTestCase {
    private func reference(_ raw: String) -> Date? {
        let sql = DateFormatter()
        sql.locale = Locale(identifier: "en_US_POSIX")
        sql.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mm:ss'Z'", "yyyy-MM-dd HH:mm:ss"] {
            sql.dateFormat = format
            if let date = sql.date(from: raw) { return date }
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        return iso.date(from: raw)
    }

    func testMatchesTheFormatters() throws {
        for raw in ["2026-10-18 00:45:14Z", "2026-10-20 10:00:00", "2026-10-19T01:00:00.000Z", "2026-10-19T01:00:00Z",
                    "2024-02-29 23:59:59Z", "1999-12-31T23:59:59.123Z", "2026-03-29 01:30:00"] {
            let expected = try XCTUnwrap(reference(raw), raw)
            let fast = try XCTUnwrap(ServerDate.parse(raw), raw)
            XCTAssertEqual(fast.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.0005, raw)
        }
    }

    func testOtherFormatsStillWork() {
        XCTAssertNotNil(ServerDate.parse("2026-10-19T03:00:00+02:00"), "an offset goes to the full parser")
        XCTAssertNil(ServerDate.parse("yesterday"))
        XCTAssertNil(ServerDate.parse("2026-13-40 99:99:99"))
        XCTAssertNil(ServerDate.parse(""))
    }

    /// 10,000 dates (5,000 snippets) well under a second; it took several seconds with new formatters each time.
    func testParsingIsFast() {
        let start = Date()
        for i in 0..<10_000 { _ = ServerDate.parse("2026-10-\(10 + i % 18) 12:34:\(10 + i % 50)Z") }
        XCTAssertLessThan(Date().timeIntervalSince(start), ProcessInfo.processInfo.environment["CI"] == "true" ? 2 : 0.5)
    }
}
