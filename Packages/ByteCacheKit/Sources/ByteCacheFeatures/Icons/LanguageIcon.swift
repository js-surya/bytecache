import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The icon for a snippet language (CP-23): the language's logo (Devicon), a generic symbol for
/// languages without one (SQL, config files…), or the usual </> for anything unknown.
/// Tables live in the generated LanguageIcons.swift.
public enum LanguageIcon: Equatable, Sendable {
    case logo(String)
    case generic(AppSymbol)
    case fallback

    /// Accepts ByteStash ids and the names people type on their servers ("C++", "c#", "Shell", "Astro").
    public static func `for`(_ language: String) -> LanguageIcon {
        var key = normalise(language)
        key = aliases[key] ?? key
        if let logo = logoByKey[key] { return .logo(logo) }
        if let symbol = genericByKey[key] { return .generic(symbol) }
        return .fallback
    }

    /// Lower case without spaces, dashes, underscores or dots; keeps "+" and "#" ("c++", "c#").
    static func normalise(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .filter { !" -_.".contains($0) }
    }

    /// A colour for Colour mode when the icon has none of its own: a black logo (Rust, Markdown) or a
    /// generic icon (SQL, TOML). Nil when the icon is already in colour or the language's colour is
    /// black, white or grey. Tables live in the generated LanguageTints.swift.
    public static func tint(for language: String) -> Tint? {
        var key = normalise(language)
        key = aliases[key] ?? key
        if let logo = logoByKey[key] { return darkLogos.contains(logo) ? logoTints[logo] : nil }
        return genericTints[key]
    }

    /// Every tint, for tests.
    static var allTints: [String: Tint] {
        logoTints.merging(genericTints) { first, _ in first }
    }

    /// A light- and a dark-mode shade of one colour (0xRRGGBB), each readable on its background.
    public struct Tint: Equatable, Sendable {
        public let light: UInt32
        public let dark: UInt32

        var color: Color {
            #if canImport(UIKit)
            Color(UIColor { $0.userInterfaceStyle == .dark ? Self.platformColor(dark) : Self.platformColor(light) })
            #else
            Color(NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? Self.platformColor(dark) : Self.platformColor(light)
            })
            #endif
        }

        #if canImport(UIKit)
        private static func platformColor(_ rgb: UInt32) -> UIColor {
            UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        #else
        private static func platformColor(_ rgb: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        #endif
    }

    /// For tests: an image from the package's asset catalog.
    static func image(named name: String) -> Any? {
        #if canImport(UIKit)
        UIImage(named: name, in: .module, compatibleWith: nil)
        #else
        Bundle.module.image(forResource: name)
        #endif
    }
}

public enum LanguageIconStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case color, monochrome
    public var id: String { rawValue }
    public var title: String { self == .color ? "Colour" : "Monochrome" }
}

/// A language's icon at the given size, in the style chosen in Settings → Appearance.
public struct LanguageIconView: View {
    let language: String
    var size: CGFloat = 16
    /// Overrides the Settings choice (the Appearance preview shows both).
    var style: LanguageIconStyle?
    @Environment(AppSettings.self) private var settings
    @Environment(\.iconStyle) private var iconStyle

    public init(_ language: String, size: CGFloat = 16, style: LanguageIconStyle? = nil) {
        self.language = language
        self.size = size
        self.style = style
    }

    private var inColour: Bool { (style ?? settings.languageIconStyle) == .color }

    public var body: some View {
        Group {
            switch LanguageIcon.for(language) {
            case .logo(let name):
                if inColour && !LanguageIcon.darkLogos.contains(name) {
                    Image("lang-\(name)-color", bundle: .module).resizable()
                } else if inColour, let tint = LanguageIcon.tint(for: language) {
                    Image("lang-\(name)-mono", bundle: .module).resizable().renderingMode(.template)
                        .foregroundStyle(tint.color)
                } else {
                    Image("lang-\(name)-mono", bundle: .module).resizable().renderingMode(.template)
                }
            case .generic(let symbol):
                if inColour, let tint = LanguageIcon.tint(for: language) {
                    symbol.image(iconStyle).resizable().foregroundStyle(tint.color)
                } else {
                    symbol.image(iconStyle).resizable()
                }
            case .fallback:
                AppSymbol.code.image(iconStyle).resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
