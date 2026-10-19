import Foundation

/// Reorders the classifier's candidates for look-alike languages using unmistakable syntax.
/// A rule only promotes a language the classifier already ranked; it never invents one.
enum Disambiguator {
    private struct Rule: @unchecked Sendable {
        let target: String
        let rivals: Set<String>
        let signal: Regex<AnyRegexOutput>
        var unless: Regex<AnyRegexOutput>?
    }

    /// How deep into the classifier ranking a rule may reach for its target.
    static let rankingWindow = 10

    /// Confidence given to a promoted language, so the detector treats the rule's verdict as certain.
    static let promotedConfidence = 0.75

    private static func re(_ pattern: String) -> Regex<AnyRegexOutput> {
        try! Regex(pattern)
    }

    nonisolated(unsafe) private static let cppSignal = re(#"std::|template\s*<|#include\s*<(iostream|vector|string|map|memory|algorithm|unordered_map)>|\bnamespace\s+\w+|\bnullptr\b|^\s*(public|private|protected):|\bcout\s*<<"#)

    nonisolated(unsafe) private static let rules: [Rule] = [
        Rule(target: "cpp", rivals: ["c"], signal: cppSignal.anchorsMatchLineEndings()),
        Rule(target: "c", rivals: ["cpp"],
             signal: re(#"#include\s*<(stdio|stdlib|string|unistd|stdint)\.h>|\bprintf\s*\(|\bmalloc\s*\("#),
             unless: cppSignal.anchorsMatchLineEndings()),
        Rule(target: "typescript", rivals: ["javascript"],
             signal: re(#":\s*(string|number|boolean|any|void|unknown|never)\b|\binterface\s+\w+\s*\{|\bas\s+const\b|\btype\s+\w+\s*=|\bimplements\s+\w+|\b(private|public|readonly)\s+\w+\s*[:;=(]|\benum\s+\w+\s*\{"#)),
        Rule(target: "swift", rivals: ["kotlin", "scala", "groovy", "java"],
             signal: re(#"\bguard\s+let\b|\bif\s+let\b|\bfunc\s+\w+|import\s+(UIKit|SwiftUI|Foundation)\b|@State\b"#)),
        Rule(target: "kotlin", rivals: ["swift", "scala", "groovy", "java"],
             signal: re(#"\bfun\s+\w+|\?:|\bdata\s+class\b|\bwhen\s*\("#)),
        Rule(target: "scala", rivals: ["kotlin", "swift", "groovy", "java"],
             signal: re(#"\bcase\s+class\b|\bdef\s+\w+|\bimplicit\b|\btrait\s+\w+"#)),
        Rule(target: "vimscript", rivals: ["markdown", "bash", "lua", "yaml"],
             signal: re(#"^\s*(set|setlocal|nnoremap|nmap|noremap|inoremap|vnoremap|autocmd|augroup|let\s+[gbswl]:|syntax|filetype|colorscheme|command!?)\b"#).anchorsMatchLineEndings()),
        Rule(target: "powershell", rivals: ["bash", "yaml"],
             signal: re(#"\$PSVersionTable|\b(Get|Set|New|Remove|Write|Where|ForEach|Select|Invoke|Import)-[A-Z]\w+|\s-(eq|ne|gt|lt|ge|le|like|match)\s|\$_\b|\bparam\s*\("#)),
        Rule(target: "bash", rivals: ["powershell"],
             signal: re(#"\b(then|fi|elif|esac|done)\b|\[\s+-[a-z]\s|(^|&&\s*|;\s*)sudo\s|\bapt(-get)?\s+install\b|\bexport\s+[A-Z_]+="#)),
        Rule(target: "java", rivals: ["apex", "kotlin", "groovy", "scala", "csharp"],
             signal: re(#"System\.out\.|\bimport\s+java\.|public\s+static\s+void\s+main\s*\("#)),
        Rule(target: "python", rivals: ["julia", "matlab", "ruby", "vyper", "r", "elm"],
             signal: re(#"\bin\s+range\(|^\s*from\s+[\w.]+\s+import\s|\belif\b|^\s*def\s+\w+\(.*\)\s*(->\s*[^:]+)?:\s*$|\bself\.\w+"#).anchorsMatchLineEndings(),
             unless: re(#"@(external|internal|view|pure|payable)\b|\bpublic\(|#\s*@version"#)),
    ]

    static func refine(text: String, ranked: [LanguageGuess]) -> [LanguageGuess] {
        guard let top = ranked.first else { return ranked }
        let candidates = ranked.prefix(rankingWindow)
        for rule in rules where rule.rivals.contains(top.id) {
            guard let index = candidates.firstIndex(where: { $0.id == rule.target }),
                  text.contains(rule.signal),
                  rule.unless.map({ !text.contains($0) }) ?? true else { continue }
            var promoted = ranked[index]
            promoted.confidence = max(promoted.confidence, top.confidence, promotedConfidence)
            var result = ranked
            result.remove(at: index)
            result.insert(promoted, at: 0)
            return result
        }
        // A rival rule may confirm the classifier's own choice; lift it past the threshold.
        for rule in rules where rule.target == top.id && text.contains(rule.signal) {
            if let unless = rule.unless, text.contains(unless) { continue }
            var result = ranked
            result[0].confidence = max(top.confidence, promotedConfidence)
            return result
        }
        return ranked
    }
}
