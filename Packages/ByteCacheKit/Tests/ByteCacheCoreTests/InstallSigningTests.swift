import XCTest
@testable import ByteCacheCore

/// CP-42: sideloaded copies are re-signed, so the App Group and keychain group come from the install.
final class InstallSigningTests: XCTestCase {
    private func profileData(groups: [String], prefix: String) -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>ApplicationIdentifierPrefix</key><array><string>\(prefix)</string></array>
        <key>Entitlements</key><dict>
        <key>com.apple.security.application-groups</key><array>\(groups.map { "<string>\($0)</string>" }.joined())</array>
        </dict></dict></plist>
        """
        // A real profile wraps the plist in a binary signature envelope.
        return Data([0x30, 0x82, 0x01, 0x00]) + Data(plist.utf8) + Data([0x00, 0xA0, 0x82])
    }

    func testReadsGroupsAndTeamFromTheProfile() {
        let signing = InstallSigning.profile(profileData(groups: ["group.app.bytecache.ABCDE12345", "group.*"], prefix: "ABCDE12345"))
        XCTAssertEqual(signing, InstallSigning(appGroups: ["group.app.bytecache.ABCDE12345"], teamPrefix: "ABCDE12345"))
    }

    func testNotAProfile() {
        XCTAssertNil(InstallSigning.profile(Data("hello".utf8)))
    }

    func testDeclaredGroupWinsWhenItWorks() {
        let signing = InstallSigning(appGroups: ["group.app.bytecache.ABCDE12345"])
        XCTAssertEqual(signing.appGroup(declared: "group.app.bytecache") { _ in true }, "group.app.bytecache")
    }

    func testFallsBackToTheGroupThisCopyWasGiven() {
        let signing = InstallSigning(appGroups: ["group.other", "group.app.bytecache.ABCDE12345"])
        XCTAssertEqual(signing.appGroup(declared: "group.app.bytecache") { $0 != "group.app.bytecache" },
                       "group.app.bytecache.ABCDE12345")
    }

    func testNoUsableGroup() {
        XCTAssertNil(InstallSigning().appGroup(declared: "group.app.bytecache") { _ in false })
    }

    func testKeychainGroupGetsThisCopysTeamPrefix() {
        let signing = InstallSigning(teamPrefix: "ABCDE12345")
        XCTAssertEqual(signing.keychainGroup(declared: "app.bytecache.shared"), "ABCDE12345.app.bytecache.shared")
        XCTAssertEqual(signing.keychainGroup(declared: "ZZZZZ99999.app.bytecache.shared"), "ABCDE12345.app.bytecache.shared")
        XCTAssertEqual(InstallSigning().keychainGroup(declared: "ZZZZZ99999.app.bytecache.shared"), "ZZZZZ99999.app.bytecache.shared")
    }
}
