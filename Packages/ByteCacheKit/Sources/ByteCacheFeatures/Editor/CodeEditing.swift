import Foundation

/// One change to make in the editor: replace `range` with `replacement`, then select `selection`.
/// Ranges are UTF-16, as text views use.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange
}

/// Editor behaviour that doesn't depend on UIKit/AppKit: indenting, bracket pairs, line numbers.
public enum CodeEditing {
    static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
    static let closers: Set<Character> = [")", "]", "}"]
    static let quotes: Set<Character> = ["\"", "'", "`"]

    /// Return key: keep the line's indent, add one after an opener or `:`, and split an empty `{}` pair.
    public static func newline(in text: String, selection: NSRange, indentUnit: String) -> TextEdit {
        let ns = text as NSString
        let lineStart = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let line = ns.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let before = line.trimmingCharacters(in: .whitespaces).last
        let after = character(in: ns, at: selection.location + selection.length)

        if let before, let close = pairs[before], closers.contains(close), after == close {
            let inner = "\n" + indent + indentUnit
            return TextEdit(range: selection, replacement: inner + "\n" + indent,
                            selection: NSRange(location: selection.location + (inner as NSString).length, length: 0))
        }
        let opens = before.map { "{[(:".contains($0) } ?? false
        let insert = "\n" + indent + (opens ? indentUnit : "")
        return TextEdit(range: selection, replacement: insert,
                        selection: NSRange(location: selection.location + (insert as NSString).length, length: 0))
    }

    /// A typed character: wrap the selection, add the closing pair, or step over an existing closer.
    /// Nil means "type it normally".
    public static func insert(_ typed: String, in text: String, selection: NSRange) -> TextEdit? {
        guard typed.count == 1, let char = typed.first else { return nil }
        let ns = text as NSString
        let next = character(in: ns, at: selection.location + selection.length)

        if selection.length == 0, closers.contains(char) || quotes.contains(char), next == char {
            return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "",
                            selection: NSRange(location: selection.location + 1, length: 0))
        }
        guard let close = pairs[char] else { return nil }
        if selection.length > 0 {
            let inner = ns.substring(with: selection)
            return TextEdit(range: selection, replacement: "\(char)\(inner)\(close)",
                            selection: NSRange(location: selection.location + 1, length: selection.length))
        }
        if let next, !(next.isWhitespace || closers.contains(next) || next == "," || next == ";") { return nil }
        if quotes.contains(char), let previous = character(in: ns, at: selection.location - 1),
           previous.isLetter || previous.isNumber || previous == "\\" || previous == "_" {
            return nil
        }
        return TextEdit(range: selection, replacement: "\(char)\(close)",
                        selection: NSRange(location: selection.location + 1, length: 0))
    }

    /// Backspace between an empty pair such as `(|)` removes both.
    public static func deleteBackward(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0, selection.location > 0 else { return nil }
        let ns = text as NSString
        guard let previous = character(in: ns, at: selection.location - 1), let close = pairs[previous],
              character(in: ns, at: selection.location) == close else { return nil }
        return TextEdit(range: NSRange(location: selection.location - 1, length: 2), replacement: "",
                        selection: NSRange(location: selection.location - 1, length: 0))
    }

    /// The bracket next to the caret (before it first) and its partner, as UTF-16 offsets.
    public static func matchingBracket(in text: String, caret: Int) -> (bracket: Int, match: Int)? {
        let ns = text as NSString
        for position in [caret - 1, caret] {
            guard let char = character(in: ns, at: position) else { continue }
            if let close = pairs[char], closers.contains(close),
               let match = scan(ns, from: position + 1, step: 1, open: char, close: close) {
                return (position, match)
            }
            if closers.contains(char), let open = pairs.first(where: { $0.value == char })?.key,
               let match = scan(ns, from: position - 1, step: -1, open: char, close: open) {
                return (position, match)
            }
        }
        return nil
    }

    /// Tabs if any line starts with one, otherwise the smallest space indent (2–8), else four spaces.
    public static func indentUnit(for text: String) -> String {
        var smallest = Int.max
        for line in text.split(separator: "\n") {
            if line.first == "\t" { return "\t" }
            let spaces = line.prefix { $0 == " " }.count
            if spaces >= 2, spaces < line.count { smallest = min(smallest, spaces) }
        }
        return smallest <= 8 ? String(repeating: " ", count: smallest) : "    "
    }

    /// UTF-16 offset where each line starts; always at least one line.
    public static func lineStarts(in text: String) -> [Int] {
        var starts = [0]
        for (offset, unit) in text.utf16.enumerated() where unit == 10 { starts.append(offset + 1) }
        return starts
    }

    // MARK: Private

    private static func character(in ns: NSString, at location: Int) -> Character? {
        guard location >= 0, location < ns.length else { return nil }
        return ns.substring(with: ns.rangeOfComposedCharacterSequence(at: location)).first
    }

    /// Walks from `from` until the bracket that balances `open` (depth counting; strings aren't skipped).
    private static func scan(_ ns: NSString, from: Int, step: Int, open: Character, close: Character) -> Int? {
        let openUnit = String(open).utf16.first!, closeUnit = String(close).utf16.first!
        var depth = 0, position = from
        var budget = 20_000
        while position >= 0, position < ns.length, budget > 0 {
            let unit = ns.character(at: position)
            if unit == openUnit { depth += 1 }
            if unit == closeUnit {
                if depth == 0 { return position }
                depth -= 1
            }
            position += step
            budget -= 1
        }
        return nil
    }
}
