import ByteCacheLanguage
import XCTest
@testable import ByteCacheFeatures

/// CP-23: each language gets its own icon; unknown ones keep the generic </> icon.
final class LanguageIconTests: XCTestCase {
    func testBuiltInLanguagesHaveLogosOrAFittingGenericIcon() {
        for id in LanguageCatalog.ids {
            let icon = LanguageIcon.for(id)
            switch icon {
            case .logo, .generic: break
            case .fallback: XCTAssertTrue(["abap", "x3"].contains(id), "\(id) should have an icon")
            }
        }
        XCTAssertEqual(LanguageIcon.for("python"), .logo("python"))
        XCTAssertEqual(LanguageIcon.for("cpp"), .logo("cplusplus"))
        XCTAssertEqual(LanguageIcon.for("dockerfile"), .logo("docker"))
        XCTAssertEqual(LanguageIcon.for("sql"), .generic(.database))
        XCTAssertEqual(LanguageIcon.for("batch"), .generic(.terminal))
        XCTAssertEqual(LanguageIcon.for("plaintext"), .generic(.plainText))
    }

    func testNamesAndAliasesAreNormalised() {
        XCTAssertEqual(LanguageIcon.for("C++"), .logo("cplusplus"))
        XCTAssertEqual(LanguageIcon.for("c#"), .logo("csharp"))
        XCTAssertEqual(LanguageIcon.for("sh"), .logo("bash"))
        XCTAssertEqual(LanguageIcon.for("Shell"), .logo("bash"))
        XCTAssertEqual(LanguageIcon.for("js"), .logo("javascript"))
        XCTAssertEqual(LanguageIcon.for("yml"), .logo("yaml"))
        XCTAssertEqual(LanguageIcon.for(" Golang "), .logo("go"))
        XCTAssertEqual(LanguageIcon.for("Astro"), .logo("astro"), "custom server languages get logos too")
        XCTAssertEqual(LanguageIcon.for("Docker"), .logo("docker"))
    }

    func testUnknownLanguagesFallBack() {
        XCTAssertEqual(LanguageIcon.for("Martin"), .fallback)
        XCTAssertEqual(LanguageIcon.for(""), .fallback)
    }

    func testEveryLogoShipsInBothStyles() {
        for name in LanguageIcon.allLogos {
            XCTAssertNotNil(LanguageIcon.image(named: "lang-\(name)-color"), "\(name) colour")
            XCTAssertNotNil(LanguageIcon.image(named: "lang-\(name)-mono"), "\(name) monochrome")
        }
        XCTAssertGreaterThan(LanguageIcon.allLogos.count, 60)
    }

    func testBlackLogosFollowTheTextColourInColourMode() {
        XCTAssertTrue(LanguageIcon.darkLogos.contains("rust"), "the Rust logo is black")
        XCTAssertFalse(LanguageIcon.darkLogos.contains("python"))
    }

    func testDevIconLicenceShipsWithTheApp() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "DEVICON-LICENSE", withExtension: "txt"))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("MIT License"))
    }
}
