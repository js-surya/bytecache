import Foundation

/// The order lists show: pinned first (as ByteStash does), in the person's own order when they set one
/// (new pins on top), then by the chosen sort.
/// A–Z ignores case and compares numbers naturally, like Finder; ByteStash itself sorts
/// by byte value, which puts every capitalised title before every lowercase one.
public enum SnippetOrdering {
    public static func arranged(_ snippets: [Snippet], by sort: SnippetSort, pinnedFirst: Bool = true,
                                pinOrder: [Int] = []) -> [Snippet] {
        let indexed = snippets.enumerated().map { (offset: $0.offset, snippet: $0.element) }
        let rank = Dictionary(pinOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return indexed.sorted { a, b in
            if pinnedFirst, a.snippet.isPinned != b.snippet.isPinned { return a.snippet.isPinned }
            if pinnedFirst, a.snippet.isPinned, !rank.isEmpty {
                // Pins without a place (new ones) first, by the sort; then the person's order.
                switch (rank[a.snippet.id], rank[b.snippet.id]) {
                case let (x?, y?): return x < y
                case (nil, _?): return true
                case (_?, nil): return false
                case (nil, nil): break
                }
            }
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
