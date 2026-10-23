import XCTest
@testable import ByteCacheFeatures

/// The crash toast goes at the first interaction; the "Copied" toast just times out.
@MainActor
final class ToastTests: XCTestCase {
    func testDismissOnInteractionAndHide() {
        let toast = CopyToastModel()
        var shownFor: Duration?
        toast.onShow = { shownFor = $0 }

        toast.show("Copied")
        XCTAssertFalse(toast.dismissesOnInteraction)
        XCTAssertEqual(shownFor, .seconds(1.6))

        toast.show("ByteCache closed unexpectedly.", symbol: .warning, for: .seconds(4), dismissOnInteraction: true)
        XCTAssertTrue(toast.dismissesOnInteraction)
        XCTAssertEqual(toast.symbol, .warning)
        XCTAssertEqual(shownFor, .seconds(4))

        toast.hide()
        XCTAssertNil(toast.message)
        XCTAssertFalse(toast.dismissesOnInteraction)
    }
}
