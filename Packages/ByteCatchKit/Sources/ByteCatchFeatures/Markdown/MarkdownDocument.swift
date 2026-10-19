import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    public enum ListMarker: Equatable, Sendable {
        case bullet
        case number(Int)
        case task(done: Bool)
    }

    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(marker: ListMarker, depth: Int, text: String)
    case quote(String)
    case code(language: String?, text: String)
    case rule
}

/// A small block-level Markdown reader for previews: headings, paragraphs, lists (bullets, numbers,
/// tasks, nesting), quotes, fenced code and rules. Inline styling is left to `inline(_:)`.
public enum MarkdownDocument {
    public static func isMarkdown(language: String) -> Bool {
        language == "markdown"
    }

    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: " "))) }
            paragraph = []
            quote = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            index += 1

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                index += 1 // closing fence (or past the end)
                blocks.append(.code(language: language.isEmpty ? nil : language, text: code.joined(separator: "\n")))
                continue
            }
            if trimmed.isEmpty {
                flush()
                continue
            }
            if let match = trimmed.wholeMatch(of: /(#{1,6})\s+(.*?)\s*#*/) {
                flush()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
                continue
            }
            if trimmed.wholeMatch(of: /([-*_])(\s*\1){2,}/) != nil {
                flush()
                blocks.append(.rule)
                continue
            }
            if let match = line.wholeMatch(of: /(\s*)[-*+]\s+\[([ xX])\]\s+(.*)/) {
                flush()
                blocks.append(.listItem(marker: .task(done: match.2 != " "), depth: depth(match.1), text: String(match.3)))
                continue
            }
            if let match = line.wholeMatch(of: /(\s*)[-*+]\s+(.*)/) {
                flush()
                blocks.append(.listItem(marker: .bullet, depth: depth(match.1), text: String(match.2)))
                continue
            }
            if let match = line.wholeMatch(of: /(\s*)(\d{1,9})[.)]\s+(.*)/) {
                flush()
                blocks.append(.listItem(marker: .number(Int(match.2) ?? 1), depth: depth(match.1), text: String(match.3)))
                continue
            }
            if let match = trimmed.wholeMatch(of: />\s?(.*)/) {
                if !paragraph.isEmpty { flush() }
                quote.append(String(match.1))
                continue
            }
            if !quote.isEmpty { flush() }
            paragraph.append(trimmed)
        }
        flush()
        return blocks
    }

    /// Bold, italic, code spans, strikethrough and links; plain text if the Markdown is malformed.
    public static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func depth(_ indent: Substring) -> Int {
        indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
    }
}
