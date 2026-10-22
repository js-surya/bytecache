import XCTest
@testable import ByteCacheFeatures

/// Apple Intelligence isn't on every device: unsupported ones hide the features, the rest say what's missing.
final class AIAvailabilityTests: XCTestCase {
    /// Hidden wherever Apple doesn't say the device supports it; shown (with what to do) where it does.
    func testHiddenUnlessAppleSaysTheDeviceSupportsIt() {
        XCTAssertTrue(AIAvailability.deviceNotSupported.hidesFeatures)
        XCTAssertTrue(AIAvailability.needsNewerSystem.hidesFeatures, "no guessing whether an update would bring it")
        for state in [AIAvailability.available, .turnedOff, .notReady] {
            XCTAssertFalse(state.hidesFeatures, "\(state)")
        }
    }

    func testNoPromisesAboutSupport() {
        for state in [AIAvailability.needsNewerSystem, .deviceNotSupported] {
            let text = state.explanation ?? ""
            XCTAssertFalse(text.contains("26") || text.lowercased().contains("supported"), text)
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
