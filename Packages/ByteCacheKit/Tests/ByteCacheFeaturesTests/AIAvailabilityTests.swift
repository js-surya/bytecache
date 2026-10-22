import XCTest
@testable import ByteCacheFeatures

/// Apple Intelligence isn't on every device: unsupported ones hide the features, the rest say what's missing.
final class AIAvailabilityTests: XCTestCase {
    func testOnlyUnsupportedHardwareHidesTheFeatures() {
        XCTAssertTrue(AIAvailability.deviceNotSupported.hidesFeatures)
        for state in [AIAvailability.available, .needsNewerSystem, .turnedOff, .notReady] {
            XCTAssertFalse(state.hidesFeatures, "\(state)")
        }
    }

    func testEveryUnavailableStateSaysWhy() {
        XCTAssertNil(AIAvailability.available.explanation)
        for state in [AIAvailability.needsNewerSystem, .deviceNotSupported, .turnedOff, .notReady] {
            XCTAssertFalse(state.explanation?.isEmpty ?? true, "\(state)")
        }
        XCTAssertTrue(AIAvailability.turnedOff.explanation?.contains("Apple Intelligence & Siri") == true)
    }

    func testCurrentMatchesWhetherSuggestionsWork() {
        // On this Mac, whatever its state: Suggest is offered exactly when the model is available.
        XCTAssertEqual(AIAvailability.current == .available, SnippetSuggesters.onDevice() != nil)
    }
}
