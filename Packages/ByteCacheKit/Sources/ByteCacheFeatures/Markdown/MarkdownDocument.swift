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
    /// A GitHub-style table (CP-73). Rows are padded or cut to the header's width.
    case table(header: [String], alignments: [TableAlignment], rows: [[String]])

    public enum TableAlignment: Equatable, Sendable { case leading, center, trailing }
}

/// A small block-level Markdown reader for previews: headings, paragraphs, lists (bullets, numbers,
/// tasks, nesting), quotes, fenced code, rules and tables. Inline styling is left to `inline(_:)`.
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
            if trimmed.contains("|"), index < lines.count, let alignments = tableAlignments(lines[index]) {
                let header = tableCells(trimmed)
                if header.count == alignments.count {
                    flush()
                    index += 1
                    var rows: [[String]] = []
                    while index < lines.count {
                        let row = lines[index].trimmingCharacters(in: .whitespaces)
                        guard !row.isEmpty, row.contains("|") else { break }
                        let cells = tableCells(row)
                        rows.append((0..<header.count).map { $0 < cells.count ? cells[$0] : "" })
                        index += 1
                    }
                    blocks.append(.table(header: header, alignments: alignments, rows: rows))
                    continue
                }
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

    /// The cells of a table row: outer pipes optional, `\|` is a literal pipe.
    static func tableCells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") && !row.hasSuffix("\\|") { row.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in row {
            if escaped {
                current.append(character == "|" ? "|" : "\\\(character)")
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// The divider under a table's header ("|:--|:-:|--:|"), read as each column's alignment.
    static func tableAlignments(_ line: String) -> [MarkdownBlock.TableAlignment]? {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [MarkdownBlock.TableAlignment] = []
        for cell in cells {
            guard cell.wholeMatch(of: /:?-+:?/) != nil else { return nil }
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): alignments.append(.center)
            case (false, true): alignments.append(.trailing)
            default: alignments.append(.leading)
            }
        }
        return alignments
    }

    private static func depth(_ indent: Substring) -> Int {
        indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
    }
}
