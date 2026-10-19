import XCTest
@testable import ByteCatchFeatures

final class FakeAuthenticator: Authenticating, @unchecked Sendable {
    var result = true
    var available = true
    var calls = 0
    var biometry: BiometryKind = .faceID
    var canAuthenticate: Bool { available }
    func authenticate(reason: String) async -> Bool {
        calls += 1
        return result
    }
}

@MainActor
final class AppLockTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000)
    private let auth = FakeAuthenticator()

    private func defaults() -> UserDefaults {
        let name = "bytecatch.lock.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    private func model(_ d: UserDefaults? = nil) -> AppLockModel {
        AppLockModel(defaults: d ?? defaults(), authenticator: auth, now: { [unowned self] in self.now })
    }

    func testOffByDefaultAndNeverLocks() {
        let lock = model()
        XCTAssertFalse(lock.isEnabled)
        lock.appDidLaunch()
        XCTAssertFalse(lock.isLocked)
    }

    func testTurningOnNeedsAuthenticationAndPersists() async {
        let d = defaults()
        let lock = model(d)
        auth.result = false
        let refused = await lock.setEnabled(true)
        XCTAssertFalse(refused)
        XCTAssertFalse(lock.isEnabled)
        auth.result = true
        let accepted = await lock.setEnabled(true)
        XCTAssertTrue(accepted)
        XCTAssertTrue(model(d).isEnabled)
    }

    func testTurningOffAlsoNeedsAuthentication() async {
        let lock = model()
        _ = await lock.setEnabled(true)
        auth.result = false
        let refused = await lock.setEnabled(false)
        XCTAssertFalse(refused)
        XCTAssertTrue(lock.isEnabled)
    }

    func testCannotTurnOnWithoutBiometricsOrPasscode() async {
        auth.available = false
        let lock = model()
        let accepted = await lock.setEnabled(true)
        XCTAssertFalse(accepted)
        XCTAssertEqual(auth.calls, 0)
    }

    func testLocksOnLaunchAndUnlocks() async {
        let d = defaults()
        _ = await model(d).setEnabled(true)
        let lock = model(d)
        lock.appDidLaunch()
        XCTAssertTrue(lock.isLocked)
        auth.result = false
        _ = await lock.unlock()
        XCTAssertTrue(lock.isLocked)
        auth.result = true
        _ = await lock.unlock()
        XCTAssertFalse(lock.isLocked)
    }

    func testTimeoutOnReturn() async {
        let lock = model()
        _ = await lock.setEnabled(true)
        lock.timeout = .fiveMinutes
        lock.didLeaveApp()
        now += 299
        lock.didReturnToApp()
        XCTAssertFalse(lock.isLocked, "back within 5 minutes")
        lock.didLeaveApp()
        now += 300
        lock.didReturnToApp()
        XCTAssertTrue(lock.isLocked)
    }

    func testImmediatelyLocksOnAnyReturn() async {
        let lock = model()
        _ = await lock.setEnabled(true)
        lock.timeout = .immediately
        lock.didLeaveApp()
        lock.didReturnToApp()
        XCTAssertTrue(lock.isLocked)
    }

    func testWidgetsCanReadTheLockSetting() async {
        let d = defaults()
        _ = await model(d).setEnabled(true)
        XCTAssertTrue(AppLockModel.isEnabled(in: d))
    }
}
