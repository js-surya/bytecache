import Foundation

/// Values shared between the app and its extensions, read from Info.plist.
public enum AppEnvironment {
    /// App Group identifier (`BCAppGroupID`, differs per platform). On iPhone/iPad a sideloaded copy
    /// is re-signed with another group, so this is the group the install really has; nil when it has
    /// none (the app and its extensions then can't share data).
    public static var appGroupID: String? { resolved.appGroup }

    /// Shared keychain access group (`BCKeychainGroup`), with the installed copy's team prefix.
    public static var keychainGroup: String? { resolved.keychainGroup }

    private static let resolved: (appGroup: String?, keychainGroup: String?) = {
        let declaredGroup = Bundle.main.object(forInfoDictionaryKey: "BCAppGroupID") as? String
        let declaredKeychain = Bundle.main.object(forInfoDictionaryKey: "BCKeychainGroup") as? String
        #if os(iOS)
        let signing = InstallSigning.current()
        let group = signing.appGroup(declared: declaredGroup) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
        return (group, signing.keychainGroup(declared: declaredKeychain))
        #else
        return (declaredGroup, declaredKeychain)
        #endif
    }()

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
