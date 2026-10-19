import XCTest
@testable import ByteCatchFeatures

/// CP-17: one helper for all haptics, honouring the user's setting.
@MainActor
final class HapticsTests: XCTestCase {
    final class Recorder: HapticPlaying {
        var played: [(HapticEvent, Double)] = []
        func play(_ event: HapticEvent, intensity: Double) { played.append((event, intensity)) }
        func prepare() {}
    }

    private var recorder = Recorder()
    private var saved: (any HapticPlaying)!

    override func setUp() async throws {
        saved = Haptics.player
        recorder = Recorder()
        Haptics.player = recorder
    }

    override func tearDown() async throws {
        Haptics.player = saved
        Haptics.configure(enabled: true, strength: .medium)
    }

    private func settings() -> AppSettings { AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!) }

    func testStrengthSetsIntensity() {
        let s = settings()
        s.hapticStrength = .light
        Haptics.play(.tap)
        s.hapticStrength = .strong
        Haptics.play(.success)
        XCTAssertEqual(recorder.played.map(\.0), [.tap, .success])
        XCTAssertEqual(recorder.played.map(\.1), [HapticStrength.light.intensity, HapticStrength.strong.intensity])
        XCTAssertLessThan(HapticStrength.light.intensity, HapticStrength.medium.intensity)
        XCTAssertLessThan(HapticStrength.medium.intensity, HapticStrength.strong.intensity)
    }

    func testTurningOffSilencesEverything() {
        let s = settings()
        s.hapticsEnabled = false
        for event in [HapticEvent.tap, .success, .error, .selection] { Haptics.play(event) }
        XCTAssertTrue(recorder.played.isEmpty)
        s.hapticsEnabled = true
        Haptics.play(.error)
        XCTAssertEqual(recorder.played.count, 1, "applies right away, no restart")
    }

    func testSettingIsRemembered() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = AppSettings(defaults: defaults)
        XCTAssertTrue(first.hapticsEnabled)
        XCTAssertEqual(first.hapticStrength, .medium)
        first.hapticsEnabled = false
        first.hapticStrength = .strong
        let second = AppSettings(defaults: defaults)
        XCTAssertFalse(second.hapticsEnabled)
        XCTAssertEqual(second.hapticStrength, .strong)
    }

    func testScanResultsGiveFeedback() async {
        Haptics.configure(enabled: true, strength: .medium)
        _ = await ScanCodeModel(recognizer: FixedRecognizer(result: .success("print(1)"))).recognize(imageData: Data())
        _ = await ScanCodeModel(recognizer: FixedRecognizer(result: .success("  "))).recognize(imageData: Data())
        XCTAssertEqual(recorder.played.map(\.0), [.success, .error])
    }
}
