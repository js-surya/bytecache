import XCTest
@testable import ByteCacheFeatures

/// Settings → Appearance → App Icon.
@MainActor
final class AppIconTests: XCTestCase {
    final class FakeSwitcher: AppIconSwitching {
        var currentName: String?
        var fails = false
        var supportsAlternateIcons = true
        func setIcon(_ name: String?) async throws {
            struct Refused: Error {}
            if fails { throw Refused() }
            currentName = name
        }
    }

    func testDefaultIsThePrimaryIconAndOthersNameTheirIconSet() {
        XCTAssertNil(AppIconChoice.default.iconName)
        XCTAssertEqual(AppIconChoice.mint.iconName, "AppIcon-Mint")
        XCTAssertEqual(AppIconChoice(iconName: "AppIcon-Sunset"), .sunset)
        XCTAssertEqual(AppIconChoice(iconName: nil), .default)
        XCTAssertEqual(AppIconChoice(iconName: "Something-Else"), .default)
    }

    func testChoosingAnIconSwitchesAndRemembersIt() async {
        let switcher = FakeSwitcher()
        let model = AppIconModel(switcher: switcher)
        XCTAssertEqual(model.current, .default)
        await model.choose(.grape)
        XCTAssertEqual(switcher.currentName, "AppIcon-Grape")
        XCTAssertEqual(model.current, .grape)
        await model.choose(.default)
        XCTAssertNil(switcher.currentName)
        XCTAssertEqual(AppIconModel(switcher: switcher).current, .default)
    }

    func testARefusedSwitchKeepsTheIconAndSaysSo() async {
        let switcher = FakeSwitcher()
        switcher.fails = true
        let model = AppIconModel(switcher: switcher)
        await model.choose(.mint)
        XCTAssertEqual(model.current, .default)
        XCTAssertNotNil(model.errorMessage)
    }

    func testEveryChoiceHasAPreview() {
        for choice in AppIconChoice.allCases {
            XCTAssertTrue(choice.hasPreview, choice.rawValue)
        }
    }
}
