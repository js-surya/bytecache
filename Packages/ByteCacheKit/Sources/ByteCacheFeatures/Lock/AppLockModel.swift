import ByteCacheCore
import Foundation
import LocalAuthentication
import Observation

public enum BiometryKind: Sendable {
    case faceID, touchID, opticID, none

    public var name: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .none: "Passcode"
        }
    }

    public var symbol: AppSymbol {
        switch self {
        case .faceID: .faceID
        case .touchID: .touchID
        case .opticID: .opticID
        case .none: .lock
        }
    }
}

public protocol Authenticating: Sendable {
    var biometry: BiometryKind { get }
    /// Biometrics or a device passcode/password is set up.
    var canAuthenticate: Bool { get }
    func authenticate(reason: String) async -> Bool
}

/// Face ID / Touch ID / Optic ID, falling back to the device passcode or Mac password.
public struct DeviceAuthenticator: Authenticating {
    public init() {}

    public var biometry: BiometryKind {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    public var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    public func authenticate(reason: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

public enum LockTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0, oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900, oneHour = 3600
    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 Minute"
        case .fiveMinutes: "After 5 Minutes"
        case .fifteenMinutes: "After 15 Minutes"
        case .oneHour: "After 1 Hour"
        }
    }
}

/// Locks the app behind Face ID / Touch ID / passcode on launch and when coming back after the timeout.
/// The share extension and Shortcuts stay unlocked so capturing remains one step; widgets hide content.
@MainActor @Observable
public final class AppLockModel {
    nonisolated static let enabledKey = AppEnvironment.appLockEnabledKey, timeoutKey = "appLockTimeout"

    public private(set) var isEnabled: Bool
    public private(set) var isLocked = false
    public var timeout: LockTimeout { didSet { defaults.set(timeout.rawValue, forKey: Self.timeoutKey) } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticator: any Authenticating
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var authenticating = false

    public init(defaults: UserDefaults = AppEnvironment.sharedDefaults,
                authenticator: any Authenticating = DeviceAuthenticator(),
                now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.authenticator = authenticator
        self.now = now
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        timeout = LockTimeout(rawValue: defaults.integer(forKey: Self.timeoutKey)) ?? .immediately
    }

    /// For widgets: whether to hide snippet content.
    public nonisolated static func isEnabled(in defaults: UserDefaults = AppEnvironment.sharedDefaults) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    public var biometry: BiometryKind { authenticator.biometry }
    public var canAuthenticate: Bool { authenticator.canAuthenticate }

    public func appDidLaunch() {
        if isEnabled { isLocked = true }
    }

    public func didLeaveApp() {
        // Our own Face ID / passcode sheet makes the app inactive; that isn't leaving the app.
        guard !authenticating else { return }
        if leftAt == nil { leftAt = now() }
    }

    public func didReturnToApp() {
        defer { leftAt = nil }
        guard isEnabled, let leftAt, !authenticating else { return }
        if now().timeIntervalSince(leftAt) >= TimeInterval(timeout.rawValue) { isLocked = true }
    }

    @discardableResult
    public func unlock() async -> Bool {
        guard isLocked, !authenticating else { return !isLocked }
        authenticating = true
        defer { authenticating = false }
        if await authenticator.authenticate(reason: "Unlock ByteCache") { isLocked = false }
        return !isLocked
    }

    /// Turning the lock on or off asks for authentication first.
    @discardableResult
    public func setEnabled(_ on: Bool) async -> Bool {
        guard on != isEnabled else { return true }
        guard authenticator.canAuthenticate else { return false }
        authenticating = true
        defer { authenticating = false }
        let reason = on ? "Turn on App Lock" : "Turn off App Lock"
        guard await authenticator.authenticate(reason: reason) else { return false }
        isEnabled = on
        defaults.set(on, forKey: Self.enabledKey)
        WidgetSnapshotWriter.reloadAllWidgets()
        if !on { isLocked = false }
        return true
    }
}
