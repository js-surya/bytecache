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

    public var body: some View {
        Group {
            switch LanguageIcon.for(language) {
            case .logo(let name):
                if (style ?? settings.languageIconStyle) == .color && !LanguageIcon.darkLogos.contains(name) {
                    Image("lang-\(name)-color", bundle: .module).resizable()
                } else {
                    Image("lang-\(name)-mono", bundle: .module).resizable().renderingMode(.template)
                }
            case .generic(let symbol):
                symbol.image(iconStyle).resizable()
            case .fallback:
                AppSymbol.code.image(iconStyle).resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
