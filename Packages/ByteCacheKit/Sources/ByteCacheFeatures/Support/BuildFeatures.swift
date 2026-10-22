import Foundation

/// Features that depend on how the app was built (CP-63).
public enum BuildFeatures {
    /// iCloud needs an app signed by our Apple Developer team (App Store, TestFlight, the signed Mac
    /// app). The unsigned GitHub build for sideloading (`UNSIGNED_BUILD`, set by
    /// scripts/package-release.sh) is re-signed by the installer with the user's Apple ID, which
    /// can't use our iCloud container, so it leaves iCloud Sync out.
    public static let iCloud: Bool = {
        #if UNSIGNED_BUILD
        false
        #else
        true
        #endif
    }()
}
