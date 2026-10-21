import XCTest
@testable import ByteCacheCore

/// App Store and TestFlight copies update through Apple, so they must not offer GitHub downloads.
final class InstallSourceTests: XCTestCase {
    func testMacWithStoreReceiptIsAStoreInstall() {
        XCTAssertEqual(InstallSource.detect(platform: .macOS, hasStoreReceipt: true, hasProvisioningProfile: false), .appStore)
    }

    func testMacWithoutReceiptCameFromGitHubOrXcode() {
        XCTAssertEqual(InstallSource.detect(platform: .macOS, hasStoreReceipt: false, hasProvisioningProfile: false), .direct)
    }

    func testIOSDeviceWithoutProfileIsAStoreInstall() {
        // App Store and TestFlight builds carry no embedded.mobileprovision; sideloaded and Xcode builds do.
        XCTAssertEqual(InstallSource.detect(platform: .iOSDevice, hasStoreReceipt: false, hasProvisioningProfile: false), .appStore)
    }

    func testIOSDeviceWithProfileIsSideloadedOrDevelopment() {
        XCTAssertEqual(InstallSource.detect(platform: .iOSDevice, hasStoreReceipt: false, hasProvisioningProfile: true), .direct)
    }

    func testSimulatorIsNeverAStoreInstall() {
        XCTAssertEqual(InstallSource.detect(platform: .iOSSimulator, hasStoreReceipt: false, hasProvisioningProfile: false), .direct)
    }
}
