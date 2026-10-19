import Foundation

/// The order lists show: pinned first (as ByteStash does), then by the chosen sort.
/// A–Z ignores case and compares numbers naturally, like Finder; ByteStash itself sorts
/// by byte value, which puts every capitalised title before every lowercase one.
public enum SnippetOrdering {
    public static func arranged(_ snippets: [Snippet], by sort: SnippetSort, pinnedFirst: Bool = true) -> [Snippet] {
        let indexed = snippets.enumerated().map { (offset: $0.offset, snippet: $0.element) }
        return indexed.sorted { a, b in
            if pinnedFirst, a.snippet.isPinned != b.snippet.isPinned { return a.snippet.isPinned }
            switch compare(a.snippet, b.snippet, sort) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.offset < b.offset
            }
        }.map(\.snippet)
    }

    private static func compare(_ a: Snippet, _ b: Snippet, _ sort: SnippetSort) -> ComparisonResult {
        switch sort {
        case .newest: dateOrder(b, a)
        case .oldest: dateOrder(a, b)
        case .alphaAsc: a.title.localizedStandardCompare(b.title)
        case .alphaDesc: b.title.localizedStandardCompare(a.title)
        }
    }

    private static func dateOrder(_ a: Snippet, _ b: Snippet) -> ComparisonResult {
        let x = a.updatedAt ?? .distantPast, y = b.updatedAt ?? .distantPast
        return x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
    }
}
