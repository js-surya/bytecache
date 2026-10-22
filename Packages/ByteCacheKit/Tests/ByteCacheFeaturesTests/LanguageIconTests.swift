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

    func testBlackLogosAndGenericIconsGetTheLanguageColourWhereThereIsOne() {
        XCTAssertNotNil(LanguageIcon.tint(for: "rust"), "Rust's logo is black, but Rust has a colour")
        XCTAssertNotNil(LanguageIcon.tint(for: "Markdown"))
        XCTAssertNotNil(LanguageIcon.tint(for: "sql"), "no logo, but SQL has a colour")
        XCTAssertNotNil(LanguageIcon.tint(for: "toml"))
        XCTAssertNil(LanguageIcon.tint(for: "nextjs"), "Next.js is black: stays in the text colour")
        XCTAssertNil(LanguageIcon.tint(for: "plaintext"))
        XCTAssertNil(LanguageIcon.tint(for: "python"), "Python's own logo is already in colour")
    }

    /// Readable on both the light and the dark background (at least 4:1; several logos are thin outlines).
    func testTintsAreReadableInLightAndDarkMode() {
        func luminance(_ rgb: UInt32) -> Double {
            func channel(_ shift: UInt32) -> Double {
                let c = Double((rgb >> shift) & 0xFF) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        func contrast(_ a: UInt32, _ b: UInt32) -> Double {
            let (x, y) = (luminance(a), luminance(b))
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        XCTAssertGreaterThan(LanguageIcon.allTints.count, 15)
        for (name, tint) in LanguageIcon.allTints {
            XCTAssertGreaterThanOrEqual(contrast(tint.light, 0xFFFFFF), 4, "\(name) on white")
            XCTAssertGreaterThanOrEqual(contrast(tint.dark, 0x1C1C1E), 4, "\(name) on dark grey")
        }
    }

    func testLinguistLicenceShipsWithTheApp() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "LINGUIST-LICENSE", withExtension: "txt"))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("GitHub"))
    }

    func testDevIconLicenceShipsWithTheApp() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "DEVICON-LICENSE", withExtension: "txt"))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("MIT License"))
    }
}
