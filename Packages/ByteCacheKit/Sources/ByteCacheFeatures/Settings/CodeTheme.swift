import HighlightSwift
import SwiftUI

/// A colour scheme for code, as offered by popular editors.
/// Adaptive themes follow the app's light/dark appearance; fixed ones always look the same.
public struct CodeTheme: Identifiable, Hashable, Sendable {
    public enum Style: Sendable { case adaptive, light, dark }

    public struct Palette: Hashable, Sendable {
        public let colors: HighlightColors
        public let background: String
        public let foreground: String
        /// Swatch colours, read from the CSS.
        public let keyword: String
        public let string: String
    }

    public let id: String
    public let name: String
    public let style: Style
    private let light: Palette
    private let dark: Palette

    public func palette(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? dark : light
    }

    public static let defaultID = "xcode"

    public static func named(_ id: String) -> CodeTheme? {
        all.first { $0.id == id }
    }

    public static let all: [CodeTheme] = [
        adaptive("xcode", "Xcode", .xcode),
        adaptive("github", "GitHub", .github),
        adaptive("atom-one", "Atom One", .atomOne),
        adaptive("solarized", "Solarized", .solarized),
        adaptive("stackoverflow", "Stack Overflow", .stackoverflow),
        fixed("github-dark", "GitHub Dark", .dark, .dark(.github)),
        fixed("one-dark", "One Dark", .dark, .dark(.atomOne)),
        custom("dracula", "Dracula", .dark, .dracula),
        custom("monokai", "Monokai", .dark, .monokai),
        custom("nord", "Nord", .dark, .nord),
        custom("gruvbox-dark", "Gruvbox Dark", .dark, .gruvboxDark),
        custom("night-owl", "Night Owl", .dark, .nightOwl),
        custom("catppuccin-mocha", "Catppuccin Mocha", .dark, .catppuccinMocha),
        fixed("tokyo-night", "Tokyo Night", .dark, .dark(.tokyoNight)),
        fixed("solarized-dark", "Solarized Dark", .dark, .dark(.solarized)),
        fixed("panda", "Panda", .dark, .dark(.pandaSyntax)),
        fixed("github-light", "GitHub Light", .light, .light(.github)),
        fixed("one-light", "One Light", .light, .light(.atomOne)),
        custom("catppuccin-latte", "Catppuccin Latte", .light, .catppuccinLatte),
        fixed("solarized-light", "Solarized Light", .light, .light(.solarized)),
        fixed("tokyo-day", "Tokyo Night Day", .light, .light(.tokyoNight)),
        fixed("xcode-light", "Xcode Light", .light, .light(.xcode)),
    ]

    // MARK: Building

    private static func palette(_ colors: HighlightColors, isDark: Bool) -> Palette {
        let fallback = isDark ? "#dddddd" : "#222222"
        func usable(_ value: String?) -> String? {
            value.map { namedColors[$0.lowercased()] ?? $0 }.flatMap { rgb($0) == nil ? nil : $0 }
        }
        let text = usable(foreground(in: colors.css)) ?? fallback
        return Palette(colors: colors, background: colors.background, foreground: text,
                       keyword: usable(ruleColor(in: colors.css, selector: ".hljs-keyword")) ?? text,
                       string: usable(ruleColor(in: colors.css, selector: ".hljs-string")) ?? text)
    }

    private static func adaptive(_ id: String, _ name: String, _ theme: HighlightTheme) -> CodeTheme {
        CodeTheme(id: id, name: name, style: .adaptive,
                  light: palette(.light(theme), isDark: false), dark: palette(.dark(theme), isDark: true))
    }

    private static func fixed(_ id: String, _ name: String, _ style: Style, _ colors: HighlightColors) -> CodeTheme {
        let p = palette(colors, isDark: style == .dark)
        return CodeTheme(id: id, name: name, style: style, light: p, dark: p)
    }

    private static func custom(_ id: String, _ name: String, _ style: Style, _ spec: CustomPalette) -> CodeTheme {
        fixed(id, name, style, .custom(css: spec.css, background: spec.background))
    }

    private static let namedColors = [
        "white": "#ffffff", "black": "#000000", "gray": "#808080", "grey": "#808080", "silver": "#c0c0c0",
    ]

    /// The `color` declared on the `.hljs` rule.
    static func foreground(in css: String) -> String? {
        guard let start = css.range(of: ".hljs{") else { return nil }
        let body = css[start.upperBound...].prefix { $0 != "}" }
        for declaration in body.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "color" {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// The colour of the last CSS rule whose selector list includes `selector` exactly.
    static func ruleColor(in css: String, selector: String) -> String? {
        var found: String?
        for rule in css.split(separator: "}") {
            let parts = rule.split(separator: "{", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].split(separator: ",").contains(where: { $0.trimmingCharacters(in: .whitespaces) == selector })
            else { continue }
            for declaration in parts[1].split(separator: ";") {
                let kv = declaration.split(separator: ":", maxSplits: 1)
                if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == "color" {
                    found = kv[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return found
    }

    /// `#rgb`, `#rrggbb` or the same without `#`, as 0…1 components.
    public static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    public static func color(_ hex: String) -> Color {
        guard let c = rgb(hex) else { return .clear }
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

/// Official palettes of popular editor themes HighlightSwift doesn't ship, mapped onto highlight.js classes.
struct CustomPalette {
    let background, foreground, comment, keyword, string, number, function, type, builtIn, attribute, variable, tag: String

    var css: String {
        """
        .hljs{color:\(foreground);background:\(background)}\
        .hljs-comment,.hljs-quote{color:\(comment);font-style:italic}\
        .hljs-keyword,.hljs-selector-tag,.hljs-doctag,.hljs-template-tag,.hljs-meta .hljs-keyword{color:\(keyword)}\
        .hljs-string,.hljs-regexp,.hljs-addition,.hljs-meta .hljs-string,.hljs-template-variable{color:\(string)}\
        .hljs-number,.hljs-literal,.hljs-symbol,.hljs-bullet,.hljs-variable.constant_{color:\(number)}\
        .hljs-title,.hljs-title.function_,.hljs-section,.hljs-function .hljs-title{color:\(function)}\
        .hljs-type,.hljs-title.class_,.hljs-class .hljs-title,.hljs-title.class_.inherited__{color:\(type)}\
        .hljs-built_in,.hljs-meta,.hljs-selector-pseudo{color:\(builtIn)}\
        .hljs-attr,.hljs-attribute,.hljs-selector-attr,.hljs-selector-class,.hljs-selector-id,.hljs-property{color:\(attribute)}\
        .hljs-variable,.hljs-params,.hljs-variable.language_,.hljs-subst{color:\(variable)}\
        .hljs-tag,.hljs-name,.hljs-link{color:\(tag)}\
        .hljs-deletion{color:\(keyword)}.hljs-emphasis{font-style:italic}.hljs-strong{font-weight:700}
        """
    }

    static let dracula = CustomPalette(
        background: "#282a36", foreground: "#f8f8f2", comment: "#6272a4", keyword: "#ff79c6", string: "#f1fa8c",
        number: "#bd93f9", function: "#50fa7b", type: "#8be9fd", builtIn: "#8be9fd", attribute: "#50fa7b",
        variable: "#ffb86c", tag: "#ff79c6")
    static let monokai = CustomPalette(
        background: "#272822", foreground: "#f8f8f2", comment: "#75715e", keyword: "#f92672", string: "#e6db74",
        number: "#ae81ff", function: "#a6e22e", type: "#66d9ef", builtIn: "#66d9ef", attribute: "#a6e22e",
        variable: "#fd971f", tag: "#f92672")
    static let nord = CustomPalette(
        background: "#2e3440", foreground: "#d8dee9", comment: "#616e88", keyword: "#81a1c1", string: "#a3be8c",
        number: "#b48ead", function: "#88c0d0", type: "#8fbcbb", builtIn: "#88c0d0", attribute: "#8fbcbb",
        variable: "#d8dee9", tag: "#81a1c1")
    static let gruvboxDark = CustomPalette(
        background: "#282828", foreground: "#ebdbb2", comment: "#928374", keyword: "#fb4934", string: "#b8bb26",
        number: "#d3869b", function: "#fabd2f", type: "#fabd2f", builtIn: "#fe8019", attribute: "#8ec07c",
        variable: "#83a598", tag: "#fb4934")
    static let nightOwl = CustomPalette(
        background: "#011627", foreground: "#d6deeb", comment: "#637777", keyword: "#c792ea", string: "#ecc48d",
        number: "#f78c6c", function: "#82aaff", type: "#ffcb8b", builtIn: "#addb67", attribute: "#addb67",
        variable: "#d7dbe0", tag: "#7fdbca")
    static let catppuccinMocha = CustomPalette(
        background: "#1e1e2e", foreground: "#cdd6f4", comment: "#6c7086", keyword: "#cba6f7", string: "#a6e3a1",
        number: "#fab387", function: "#89b4fa", type: "#f9e2af", builtIn: "#f38ba8", attribute: "#f9e2af",
        variable: "#eba0ac", tag: "#89b4fa")
    static let catppuccinLatte = CustomPalette(
        background: "#eff1f5", foreground: "#4c4f69", comment: "#9ca0b0", keyword: "#8839ef", string: "#40a02b",
        number: "#fe640b", function: "#1e66f5", type: "#df8e1d", builtIn: "#d20f39", attribute: "#df8e1d",
        variable: "#e64553", tag: "#1e66f5")
}
