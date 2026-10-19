import HighlightSwift
import SwiftUI

/// Read-only, syntax-highlighted code in the user's code theme; scrolls sideways instead of wrapping.
public struct CodeView: View {
    let code: String
    let language: String
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    public init(code: String, language: String) {
        self.code = code
        self.language = language
    }

    private var lineNumbers: String {
        let count = max(code.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return (1...count).map(String.init).joined(separator: "\n")
    }

    public var body: some View {
        let palette = settings.codeTheme.palette(for: colorScheme)
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                if settings.showLineNumbers {
                    Text(lineNumbers)
                        .foregroundStyle(CodeTheme.color(palette.foreground).opacity(0.4))
                        .multilineTextAlignment(.trailing)
                        .accessibilityHidden(true)
                }
                CodeText(code)
                    .highlightMode(HighlightAlias.mode(for: language))
                    .codeTextColors(.custom(dark: palette.colors, light: palette.colors))
                    .foregroundStyle(CodeTheme.color(palette.foreground))
                    .textSelection(.enabled)
            }
            .font(.system(size: settings.codeFontSize, design: .monospaced))
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CodeTheme.color(palette.background))
    }
}

/// Plain text editors for code take the code theme's colours and font size.
struct CodeEditorStyle: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = settings.codeTheme.palette(for: colorScheme)
        content
            .font(.system(size: settings.codeFontSize, design: .monospaced))
            .foregroundStyle(CodeTheme.color(palette.foreground))
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(CodeTheme.color(palette.background), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    public func codeEditorStyle() -> some View { modifier(CodeEditorStyle()) }
}

/// ByteStash language id → highlight.js language bundled with HighlightSwift.
enum HighlightAlias {
    private static let overrides: [String: HighlightLanguage] = [
        "javascript": .javaScript, "typescript": .typeScript, "cpp": .cPlusPlus, "csharp": .cSharp,
        "vba": .visualBasic, "powershell": .shell, "batch": .shell, "graphql": .graphQL, "terraform": .plaintext,
        "kubernetes": .yaml, "conf": .plaintext, "ini": .toml, "webassembly": .webAssembly, "groovy": .gradle,
        "mongodb": .javaScript, "apex": .java, "solidity": .javaScript, "vyper": .python,
        "verilog": .plaintext, "systemverilog": .plaintext, "cypher": .sql, "abap": .plaintext, "x3": .plaintext,
        "vimscript": .plaintext, "xml": .html,
    ]

    static func mode(for id: String) -> HighlightMode {
        if let language = overrides[id] ?? HighlightLanguage(rawValue: id) {
            return .languageIgnoreIllegal(language)
        }
        return .language(.plaintext)
    }
}
