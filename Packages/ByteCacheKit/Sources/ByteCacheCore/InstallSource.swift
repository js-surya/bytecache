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
        let receipt = FileManager.default.fileExists(
            atPath: bundle.bundleURL.appending(path: "Contents/_MASReceipt/receipt").path(percentEncoded: false))
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

    /// A Mac store copy carries a receipt (`_MASReceipt`). On iPhone and iPad, store copies are the
    /// only ones without `embedded.mobileprovision`: Xcode, ad-hoc and sideloaded copies all have one.
    static func detect(platform: Platform, hasStoreReceipt: Bool, hasProvisioningProfile: Bool) -> InstallSource {
        switch platform {
        case .macOS: hasStoreReceipt ? .appStore : .direct
        case .iOSDevice: hasProvisioningProfile ? .direct : .appStore
        case .iOSSimulator: .direct
        }
    }
}
