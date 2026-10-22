import XCTest
@testable import ByteCacheFeatures

/// CP-70: the numbers in the snippet status bar.
final class FileStatsTests: XCTestCase {
    func testCountsLines() {
        XCTAssertEqual(FileStats("").lines, 0)
        XCTAssertEqual(FileStats("one").lines, 1)
        XCTAssertEqual(FileStats("one\ntwo").lines, 2)
        XCTAssertEqual(FileStats("one\ntwo\n").lines, 2, "a final newline doesn't start another line")
        XCTAssertEqual(FileStats("a\r\nb\r\nc").lines, 3)
    }

    func testSizeIsUTF8Bytes() {
        XCTAssertEqual(FileStats("abc").bytes, 3)
        XCTAssertEqual(FileStats("é").bytes, 2)
    }

    func testSummary() {
        XCTAssertEqual(FileStats("one").linesText, "1 line")
        XCTAssertEqual(FileStats("one\ntwo").linesText, "2 lines")
        XCTAssertEqual(FileStats(String(repeating: "x", count: 1_500_000)).linesText, "1 line")
        XCTAssertEqual(FileStats("abc").sizeText, "3 bytes")
    }
}
