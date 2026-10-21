import Foundation

/// Where this copy came from. App Store and TestFlight copies are updated by Apple, so the app
/// must not offer GitHub downloads there (App Review guidelines 2.4.5 and 2.5.2).
public enum InstallSource: Equatable, Sendable {
    /// App Store or TestFlight.
    case appStore
    /// GitHub release (sideloaded or unzipped) or an Xcode build.
    case direct

    public enum Platform: Sendable { case iOSDevice, iOSSimulator, macOS }

    public static let current: InstallSource = {
        let bundle = Bundle.main
        #if os(macOS)
        let receipts = [bundle.bundleURL.appending(path: "Contents/_MASReceipt/receipt")]
        #else
        // Next to the .app: "receipt" from the App Store, "sandboxReceipt" from TestFlight.
        let storeKit = bundle.bundleURL.deletingLastPathComponent().appending(path: "StoreKit")
        let receipts = [storeKit.appending(path: "receipt"), storeKit.appending(path: "sandboxReceipt")]
        #endif
        let receipt = receipts.contains { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        let profile = bundle.url(forResource: "embedded", withExtension: "mobileprovision") != nil
        #if os(macOS)
        let platform = Platform.macOS
        #elseif targetEnvironment(simulator)
        let platform = Platform.iOSSimulator
        #else
        let platform = Platform.iOSDevice
        #endif
        return detect(platform: platform, hasStoreReceipt: receipt, hasProvisioningProfile: profile)
    }()

    /// Store copies carry a receipt (Mac: `_MASReceipt`; iPhone and iPad: `StoreKit/receipt` or, from
    /// TestFlight, `sandboxReceipt`). On iPhone and iPad they also lack `embedded.mobileprovision`, which
    /// Xcode, ad-hoc and sideloaded copies all have; either sign is enough.
    static func detect(platform: Platform, hasStoreReceipt: Bool, hasProvisioningProfile: Bool) -> InstallSource {
        switch platform {
        case .macOS: hasStoreReceipt ? .appStore : .direct
        case .iOSDevice: hasStoreReceipt || !hasProvisioningProfile ? .appStore : .direct
        case .iOSSimulator: .direct
        }
    }
}
