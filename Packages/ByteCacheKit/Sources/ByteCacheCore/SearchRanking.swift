import Foundation

/// Orders search results by how well they match, and finds close (fuzzy) title matches.
public enum SearchRanking {
    /// Higher is better: title exact, title starts with, title contains, description, code.
    public static func score(_ snippet: Snippet, _ text: String) -> Int {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return 0 }
        let title = snippet.title
        if title.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { return 500 }
        if title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil { return 400 }
        if title.localizedCaseInsensitiveContains(query) { return 300 }
        if snippet.description.localizedCaseInsensitiveContains(query) { return 200 }
        if snippet.fragments.contains(where: { $0.fileName.localizedCaseInsensitiveContains(query) }) { return 150 }
        if snippet.fragments.contains(where: { $0.code.localizedCaseInsensitiveContains(query) }) { return 100 }
        return 0
    }

    /// Pinned first, then by score; ties keep their current (sort) order.
    public static func arranged(_ snippets: [Snippet], by text: String) -> [Snippet] {
        snippets.enumerated()
            .map { (offset: $0.offset, snippet: $0.element, score: score($0.element, text)) }
            .sorted { a, b in
                if a.snippet.isPinned != b.snippet.isPinned { return a.snippet.isPinned }
                if a.score != b.score { return a.score > b.score }
                return a.offset < b.offset
            }
            .map(\.snippet)
    }

    /// Titles that nearly match: the letters appear in order ("csvrd" → "CSV Reader"), or a word
    /// is one typo away ("pyhton" → "Python"). Best first.
    public static func closeMatches(_ snippets: [Snippet], to text: String, limit: Int = 20) -> [Snippet] {
        let query = text.lowercased().filter { !$0.isWhitespace }
        guard query.count >= 2 else { return [] }
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return snippets.compactMap { snippet -> (Snippet, Int)? in
            let title = snippet.title.lowercased()
            if let gaps = subsequenceGaps(query, in: title) { return (snippet, 1000 - gaps) }
            let titleWords = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            let typos = words.filter { $0.count >= 4 }.filter { word in
                titleWords.contains { abs($0.count - word.count) <= 1 && editDistance($0, word) <= 1 }
            }
            return typos.isEmpty ? nil : (snippet, 500 + typos.count)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }

    /// Letters skipped between matched letters when `query` is a subsequence of `title`; nil otherwise.
    static func subsequenceGaps(_ query: String, in title: String) -> Int? {
        var gaps = 0
        var index = title.startIndex
        var started = false
        for character in query {
            guard let found = title[index...].firstIndex(of: character) else { return nil }
            if started { gaps += title.distance(from: index, to: found) }
            started = true
            index = title.index(after: found)
        }
        return gaps
    }

    /// Edits (insert, delete, replace, swap two neighbours) to turn `a` into `b`.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
