import HighlightSwift
import SwiftUI

/// Read-only, syntax-highlighted code with line numbers; scrolls sideways instead of wrapping.
public struct CodeView: View {
    let code: String
    let language: String

    public init(code: String, language: String) {
        self.code = code
        self.language = language
    }

    private var lineNumbers: String {
        let count = max(code.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return (1...count).map(String.init).joined(separator: "\n")
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                Text(lineNumbers)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
                    .accessibilityHidden(true)
                CodeText(code)
                    .highlightMode(HighlightAlias.mode(for: language))
                    .codeTextColors(.theme(.xcode))
                    .textSelection(.enabled)
            }
            .font(.system(.callout, design: .monospaced))
            .padding(12)
        }
    }
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
