import Foundation

/// Values shared between the app and its extensions, read from Info.plist.
public enum AppEnvironment {
    /// App Group identifier (`BCAppGroupID`). Differs per platform.
    public static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "BCAppGroupID") as? String
    }

    /// Shared keychain access group (`BCKeychainGroup`).
    public static var keychainGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "BCKeychainGroup") as? String
    }

    /// UserDefaults shared with the share extensions; falls back to standard when no group is set.
    public static var sharedDefaults: UserDefaults {
        appGroupID.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}

extension AppEnvironment {
    /// Credentials shared with the extensions when the keychain group is available, app-local otherwise.
    public static func makeCredentialStore() -> any CredentialStore {
        FallbackCredentialStore(
            primary: KeychainCredentialStore(accessGroup: keychainGroup),
            fallback: KeychainCredentialStore(accessGroup: nil)
        )
    }
}

extension AppEnvironment {
    public static let appLockEnabledKey = "appLockEnabled"

    /// Whether App Lock is on (widgets hide snippet content when it is).
    public static var isAppLockEnabled: Bool { sharedDefaults.bool(forKey: appLockEnabledKey) }
}
