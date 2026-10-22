import HighlightSwift
import SwiftUI

/// Read-only, syntax-highlighted code in the user's code theme. Scrolls sideways, or wraps long
/// lines when Wrap Long Lines is on.
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
        (1...CodeLines.plain(code).count).map(String.init).joined(separator: "\n")
    }

    public var body: some View {
        let palette = settings.codeTheme.palette(for: colorScheme)
        Group {
            if settings.wrapLines && settings.showLineNumbers {
                WrappedCodeLines(code: code, language: language, palette: palette)
            } else if settings.wrapLines {
                highlighted(palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        if settings.showLineNumbers {
                            Text(lineNumbers)
                                .foregroundStyle(CodeTheme.color(palette.foreground).opacity(0.4))
                                .multilineTextAlignment(.trailing)
                                .accessibilityHidden(true)
                        }
                        highlighted(palette)
                    }
                    .padding(12)
                }
            }
        }
        .padding(settings.wrapLines ? 12 : 0)
        .font(.system(size: settings.codeFontSize, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CodeTheme.color(palette.background))
    }

    private func highlighted(_ palette: CodeTheme.Palette) -> some View {
        CodeText(code)
            .highlightMode(HighlightAlias.mode(for: language))
            .codeTextColors(.custom(dark: palette.colors, light: palette.colors))
            .foregroundStyle(CodeTheme.color(palette.foreground))
            .textSelection(.enabled)
    }
}

/// Wrapped code with line numbers: one row per logical line, so each number stays next to the
/// first visual line of its (possibly wrapped) line. The whole file is highlighted at once, so
/// multi-line comments and strings keep their colours.
private struct WrappedCodeLines: View {
    let code: String
    let language: String
    let palette: CodeTheme.Palette
    @State private var lines: [AttributedString]?

    private static let highlighter = Highlight()

    var body: some View {
        let rows = lines ?? CodeLines.plain(code).map { AttributedString($0) }
        let widest = String(repeating: "8", count: String(rows.count).count)
        let numberColor = CodeTheme.color(palette.foreground).opacity(0.4)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    ZStack(alignment: .trailing) {
                        Text(widest).hidden()
                        Text("\(index + 1)").foregroundStyle(numberColor)
                    }
                    .accessibilityHidden(true)
                    // An empty Text has no height; a space keeps blank lines.
                    Text(rows[index].characters.isEmpty ? AttributedString(" ") : rows[index])
                        .foregroundStyle(CodeTheme.color(palette.foreground))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .textSelection(.enabled)
        .task(id: "\(code.hashValue) \(language) \(palette.hashValue)") {
            lines = nil
            guard let result = try? await Self.highlighter.request(code, mode: HighlightAlias.mode(for: language),
                                                                    colors: palette.colors) else { return }
            // The code changed while this ran: a newer task shows the new code; don't overwrite it.
            guard !Task.isCancelled else { return }
            lines = CodeLines.split(result.attributedText, original: code)
        }
    }
}

/// Splits code into logical lines, for line numbers.
enum CodeLines {
    static func plain(_ code: String) -> [String] {
        code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Splits highlighted text into the same lines as `original`. Puts back the leading and trailing
    /// whitespace the highlighter trims. Nil if the lines don't match, to fall back to plain text.
    static func split(_ highlighted: AttributedString, original: String) -> [AttributedString]? {
        var text = highlighted
        let plainText = String(text.characters)
        if plainText != original {
            let leading = original.prefix { $0.isWhitespace }
            let trailing = String(original.reversed().prefix { $0.isWhitespace }.reversed())
            if !plainText.hasPrefix(leading) { text = AttributedString(leading) + text }
            if !trailing.isEmpty, !String(text.characters).hasSuffix(trailing) { text += AttributedString(trailing) }
        }
        var lines: [AttributedString] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.characters.index(after: index)
            if text.characters[index] == "\n" {
                lines.append(AttributedString(text[start..<index]))
                start = next
            }
            index = next
        }
        lines.append(AttributedString(text[start..<text.endIndex]))
        return lines.count == plain(original).count ? lines : nil
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
