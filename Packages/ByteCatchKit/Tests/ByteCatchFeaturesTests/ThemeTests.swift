import SwiftUI
import XCTest
@testable import ByteCatchFeatures

final class CodeThemeTests: XCTestCase {
    func testCatalogHasPopularEditorThemesWithUniqueIDs() {
        let ids = CodeTheme.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for expected in ["xcode", "github", "github-dark", "github-light", "one-dark", "one-light", "dracula", "monokai",
                         "nord", "solarized-dark", "solarized-light", "tokyo-night", "gruvbox-dark", "night-owl",
                         "catppuccin-mocha", "catppuccin-latte"] {
            XCTAssertNotNil(CodeTheme.named(expected), expected)
        }
    }

    func testEveryThemeHasParsableColours() {
        for theme in CodeTheme.all {
            for scheme in [ColorScheme.light, .dark] {
                let palette = theme.palette(for: scheme)
                XCTAssertNotNil(CodeTheme.rgb(palette.background), "\(theme.id) background \(palette.background)")
                XCTAssertNotNil(CodeTheme.rgb(palette.foreground), "\(theme.id) foreground \(palette.foreground)")
                XCTAssertTrue(palette.colors.css.contains(".hljs-keyword"), "\(theme.id) css")
            }
        }
    }

    func testFixedThemesIgnoreAppearanceAdaptiveOnesFollowIt() throws {
        let dracula = try XCTUnwrap(CodeTheme.named("dracula"))
        XCTAssertEqual(dracula.palette(for: .light), dracula.palette(for: .dark))
        XCTAssertEqual(dracula.style, .dark)
        let github = try XCTUnwrap(CodeTheme.named("github"))
        XCTAssertNotEqual(github.palette(for: .light).background, github.palette(for: .dark).background)
        XCTAssertEqual(github.style, .adaptive)
    }

    func testDarkThemesHaveDarkBackgrounds() throws {
        for theme in CodeTheme.all where theme.style == .dark {
            let rgb = try XCTUnwrap(CodeTheme.rgb(theme.palette(for: .light).background))
            XCTAssertLessThan((rgb.r + rgb.g + rgb.b) / 3, 0.35, theme.id)
        }
        for theme in CodeTheme.all where theme.style == .light {
            let rgb = try XCTUnwrap(CodeTheme.rgb(theme.palette(for: .light).background))
            XCTAssertGreaterThan((rgb.r + rgb.g + rgb.b) / 3, 0.65, theme.id)
        }
    }

    func testSwatchColoursComeFromTheCSS() throws {
        let dracula = try XCTUnwrap(CodeTheme.named("dracula")).palette(for: .dark)
        XCTAssertEqual(dracula.keyword, "#ff79c6")
        XCTAssertEqual(dracula.string, "#f1fa8c")
        for theme in CodeTheme.all {
            let p = theme.palette(for: .dark)
            XCTAssertNotNil(CodeTheme.rgb(p.keyword), "\(theme.id) keyword \(p.keyword)")
            XCTAssertNotNil(CodeTheme.rgb(p.string), "\(theme.id) string \(p.string)")
        }
    }

    func testHexParsing() {
        XCTAssertEqual(CodeTheme.rgb("#fff")?.r, 1)
        XCTAssertEqual(CodeTheme.rgb("282a36")?.g ?? 0, 42.0 / 255, accuracy: 0.001)
        XCTAssertNil(CodeTheme.rgb("not a colour"))
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "bytecatch.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testDefaults() {
        let s = AppSettings(defaults: defaults())
        XCTAssertEqual(s.appearance, .system)
        XCTAssertEqual(s.accent, .blue)
        XCTAssertEqual(s.codeTheme.id, CodeTheme.defaultID)
        XCTAssertEqual(s.codeFontSize, 14)
        XCTAssertTrue(s.showLineNumbers)
    }

    func testChangesPersistAcrossInstances() {
        let d = defaults()
        let s = AppSettings(defaults: d)
        s.appearance = .dark
        s.accent = .purple
        s.codeThemeID = "dracula"
        s.codeFontSize = 17
        s.showLineNumbers = false
        let reloaded = AppSettings(defaults: d)
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertEqual(reloaded.accent, .purple)
        XCTAssertEqual(reloaded.codeTheme.id, "dracula")
        XCTAssertEqual(reloaded.codeFontSize, 17)
        XCTAssertFalse(reloaded.showLineNumbers)
    }

    func testUnknownThemeFallsBackAndFontSizeIsClamped() {
        let d = defaults()
        d.set("no-such-theme", forKey: "codeThemeID")
        let s = AppSettings(defaults: d)
        XCTAssertEqual(s.codeTheme.id, CodeTheme.defaultID)
        s.codeFontSize = 40
        XCTAssertEqual(s.codeFontSize, AppSettings.fontSizes.upperBound)
        s.codeFontSize = 2
        XCTAssertEqual(s.codeFontSize, AppSettings.fontSizes.lowerBound)
    }

    func testAppearanceMapsToColorScheme() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }
}
