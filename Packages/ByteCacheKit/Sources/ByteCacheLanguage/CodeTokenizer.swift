import Foundation

/// Turns code into the token stream the language model sees. Training and inference must both use
/// `features(_:)`, so any change here requires retraining the model.
public enum CodeTokenizer {
    /// Identifiers longer than this are replaced by `ID` in pair features.
    static let pairIdentifierLimit = 8

    /// Tokens kept after a comment marker on the same line.
    static let commentTokenLimit = 20

    private static let commentMarkers: Set<String> = ["//", "#", "--"]

    /// Longest first, so `===` wins over `==`.
    private static let operators: [[Unicode.Scalar]] = [
        "<!--", "===", "!==", "**=", "...", "<<=", ">>=", "-->",
        "=>", "::", "->", ":=", "!=", "==", "<=", ">=", "&&", "||", "++", "--", "+=", "-=", "*=", "/=",
        "<<", ">>", "//", "/*", "*/", "<-", "|>", "<?", "?>", "<%", "%>", "..", "?.", "??", "<>", "#!",
        "{{", "}}", "@@",
    ].map { Array($0.unicodeScalars) }

    private static let operatorsByFirst: [Unicode.Scalar: [[Unicode.Scalar]]] =
        Dictionary(grouping: operators, by: { $0[0] })

    /// Readable tokens: identifiers whole, `NUM` / `STR` for literals, `NL` between lines,
    /// `INDENT` / `TAB` for leading whitespace.
    public static func tokens(_ code: String, maxLines: Int = 400) -> [String] {
        var tokens: [String] = []
        var emittedLine = false
        for line in code.split(separator: "\n", maxSplits: maxLines, omittingEmptySubsequences: false).prefix(maxLines) {
            let scalars = Array(line.unicodeScalars)
            guard scalars.contains(where: { $0 != " " && $0 != "\t" && $0 != "\r" }) else { continue }
            if emittedLine { tokens.append("NL") }
            emittedLine = true
            tokenize(line: scalars, into: &tokens)
        }
        return tokens
    }

    /// Word-safe form of `tokens` plus adjacent-pair tokens, for the text classifier.
    /// Punctuation becomes `p` + hex scalar values so word tokenizers keep it.
    public static func features(_ code: String, maxLines: Int = 400) -> String {
        let words = tokens(code, maxLines: maxLines).map(wordSafe)
        var output = words
        output.reserveCapacity(words.count * 2)
        // Pairs carry syntax shape; long names are project-specific, so they become `ID` there
        // (keeps the model small without losing keywords, which are short).
        let shapes = words.map { $0.count > pairIdentifierLimit && isIdentifierStart($0.unicodeScalars.first!) ? "ID" : $0 }
        for (a, b) in zip(shapes, shapes.dropFirst()) where a != "NL" {
            output.append(a + "ZZ" + b)
        }
        return output.joined(separator: " ")
    }

    // MARK: Private

    private static func tokenize(line s: [Unicode.Scalar], into tokens: inout [String]) {
        var i = 0
        if s.first == "\t" {
            tokens.append("TAB")
        } else if s.count > 1, s[0] == " ", s[1] == " " {
            tokens.append("INDENT")
        }
        var commentBudget: Int?

        func emit(_ token: String) -> Bool {
            if let budget = commentBudget {
                if budget == 0 { return false }
                commentBudget = budget - 1
            }
            tokens.append(token)
            return true
        }

        while i < s.count {
            let c = s[i]
            if c == " " || c == "\t" || c == "\r" || (c.value > 0x7F && c.properties.isWhitespace) {
                i += 1
            } else if isIdentifierStart(c) {
                let start = i
                while i < s.count, isIdentifierPart(s[i]) { i += 1 }
                if !emit(String(String.UnicodeScalarView(s[start..<i]))) { return }
            } else if ("0"..."9").contains(c) {
                while i < s.count, isIdentifierPart(s[i]) || s[i] == "." { i += 1 }
                if !emit("NUM") { return }
            } else if c == "\"" || c == "'" || c == "`", let end = closingQuote(s, from: i) {
                i = end + 1
                if !emit("STR") { return }
            } else {
                let candidates = operatorsByFirst[c] ?? []
                let op = candidates.first { op in
                    i + op.count <= s.count && s[i..<(i + op.count)].elementsEqual(op)
                }
                let token = op.map { String(String.UnicodeScalarView($0)) } ?? String(c)
                i += op?.count ?? 1
                if !emit(token) { return }
                if commentBudget == nil, commentMarkers.contains(token) {
                    commentBudget = commentTokenLimit
                }
            }
        }
    }

    private static func closingQuote(_ s: [Unicode.Scalar], from start: Int) -> Int? {
        let quote = s[start]
        var i = start + 1
        while i < s.count {
            if s[i] == "\\" {
                i += 2
            } else if s[i] == quote {
                return i
            } else {
                i += 1
            }
        }
        return nil
    }

    private static func isIdentifierStart(_ c: Unicode.Scalar) -> Bool {
        if c.value < 0x80 { return c == "_" || ("a"..."z").contains(c) || ("A"..."Z").contains(c) }
        return c.properties.isAlphabetic
    }

    private static func isIdentifierPart(_ c: Unicode.Scalar) -> Bool {
        isIdentifierStart(c) || ("0"..."9").contains(c)
    }

    private static func wordSafe(_ token: String) -> String {
        guard let first = token.unicodeScalars.first, !isIdentifierStart(first) else { return token }
        return "p" + token.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "x")
    }
}
