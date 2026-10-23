import XCTest
@testable import ByteCacheFeatures

/// CP-83: centred views move off the iPhone Duo fold when it's partially folded.
final class FoldAvoidanceTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 600, height: 800)

    func testNoFoldKeepsTheWholeSpace() {
        XCTAssertEqual(FoldAvoidingCenter.largestPart(of: screen, avoiding: []), screen)
    }

    func testHorizontalFoldPicksTheBiggerHalf() {
        // Laptop pose: the fold runs across, a little below the middle.
        let fold = CGRect(x: 0, y: 420, width: 600, height: 40)
        XCTAssertEqual(FoldAvoidingCenter.largestPart(of: screen, avoiding: [fold]),
                       CGRect(x: 0, y: 0, width: 600, height: 420))
    }

    func testFoldNearTheMiddlePrefersTheTopHalf() {
        // Laptop pose: both halves about the same size; the upright (top) one faces the user.
        let fold = CGRect(x: 0, y: 390, width: 600, height: 40)
        XCTAssertEqual(FoldAvoidingCenter.largestPart(of: screen, avoiding: [fold]),
                       CGRect(x: 0, y: 0, width: 600, height: 390))
    }

    func testFoldNearTheTopPicksTheBottom() {
        let fold = CGRect(x: 0, y: 200, width: 600, height: 40)
        XCTAssertEqual(FoldAvoidingCenter.largestPart(of: screen, avoiding: [fold]),
                       CGRect(x: 0, y: 240, width: 600, height: 560))
    }

    func testVerticalFoldPicksASide() {
        // Book pose: the fold runs down the middle.
        let fold = CGRect(x: 280, y: 0, width: 40, height: 800)
        let part = FoldAvoidingCenter.largestPart(of: screen, avoiding: [fold])
        XCTAssertEqual(part.size, CGSize(width: 280, height: 800))
        XCTAssertFalse(part.intersects(fold))
    }

    func testFoldOutsideTheViewChangesNothing() {
        // A column beside the fold (book pose with a split view).
        let fold = CGRect(x: 700, y: 0, width: 40, height: 800)
        XCTAssertEqual(FoldAvoidingCenter.largestPart(of: screen, avoiding: [fold]), screen)
    }
}
