import Foundation

/// Finds search matches the same way the search does (whole phrase, ignoring case), for
/// highlighting them in result rows. Matches are marked `.stronglyEmphasized`.
enum SearchHighlight {
    static func mark(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return result }
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: query, options: .caseInsensitive, range: start..<text.endIndex, locale: .current) {
            if let lower = AttributedString.Index(range.lowerBound, within: result),
               let upper = AttributedString.Index(range.upperBound, within: result) {
                result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            }
            start = range.upperBound
        }
        return result
    }

    static func contains(_ text: String, _ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        return !query.isEmpty && text.localizedCaseInsensitiveContains(query)
    }

    /// The first line of `text` containing the match, shortened in front so the match stays visible
    /// in a one-line preview.
    static func matchingLine(in text: String, query: String, lead: Int = 16) -> String? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: query, options: .caseInsensitive, locale: .current) else { continue }
            let trimmed = line.drop { $0.isWhitespace }
            let offset = trimmed.distance(from: trimmed.startIndex, to: range.lowerBound)
            guard offset > lead else { return String(trimmed) }
            return "…" + line[line.index(range.lowerBound, offsetBy: -lead)...]
        }
        return nil
    }
}
