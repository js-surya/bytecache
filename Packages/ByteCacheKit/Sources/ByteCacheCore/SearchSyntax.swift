import Foundation

/// Filters typed into the search field: `lang:python` (or `language:`), `#tag` (or `tag:`),
/// `is:pinned`, `is:favorite`. Everything else is the text to search for.
public struct SearchSyntax: Equatable, Sendable {
    public var text: String
    public var language: String?
    public var categories: [String]
    public var pinned: Bool
    public var favorite: Bool

    public init(text: String = "", language: String? = nil, categories: [String] = [],
                pinned: Bool = false, favorite: Bool = false) {
        self.text = text
        self.language = language
        self.categories = categories
        self.pinned = pinned
        self.favorite = favorite
    }

    public static func parse(_ input: String) -> SearchSyntax {
        var result = SearchSyntax()
        var words: [Substring] = []
        for token in input.split(whereSeparator: \.isWhitespace) {
            let lower = token.lowercased()
            if let value = value(of: lower, prefixes: ["lang:", "language:"]) {
                result.language = value
            } else if let value = value(of: lower, prefixes: ["#", "tag:"]) {
                if !result.categories.contains(value) { result.categories.append(value) }
            } else if lower == "is:pinned" {
                result.pinned = true
            } else if ["is:favorite", "is:favourite", "is:fav", "is:starred"].contains(lower) {
                result.favorite = true
            } else if ["lang:", "language:", "#", "tag:"].contains(lower) || lower.hasPrefix("is:") {
                // A filter still being typed: not part of the text to search for.
                continue
            } else {
                words.append(token)
            }
        }
        result.text = words.joined(separator: " ")
        return result
    }

    /// True when the input has a filter, so a server query can't find "close matches" for it.
    public var hasFilters: Bool { language != nil || !categories.isEmpty || pinned || favorite }

    private static func value(of token: String, prefixes: [String]) -> String? {
        for prefix in prefixes where token.hasPrefix(prefix) && token.count > prefix.count {
            return String(token.dropFirst(prefix.count))
        }
        return nil
    }
}

/// One suggestion for the search field: what to show, and the full text it completes to.
public struct SearchSuggestion: Equatable, Sendable, Identifiable {
    public var title: String
    public var completion: String
    public var id: String { completion }
}

extension SearchSyntax {
    /// Suggestions for the word being typed (the last one): filters, languages or tags.
    public static func suggestions(for input: String, languages: [String], categories: [String],
                                   languageName: (String) -> String = { $0 }, limit: Int = 8) -> [SearchSuggestion] {
        let endsWithSpace = input.last?.isWhitespace ?? true
        let head = endsWithSpace ? input : String(input[..<(input.lastIndex(where: \.isWhitespace).map { input.index(after: $0) } ?? input.startIndex)])
        let partial = endsWithSpace ? "" : String(input[head.endIndex...]).lowercased()
        let prefix = head.isEmpty || head.last?.isWhitespace == true ? head : head + " "
        func complete(_ token: String, _ title: String) -> SearchSuggestion {
            SearchSuggestion(title: title, completion: prefix + token + " ")
        }

        if let typed = value(ofPartial: partial, prefixes: ["lang:", "language:"]) {
            // A finished filter ("lang:python") needs no suggestion, so the results show.
            if languages.contains(where: { $0.lowercased() == typed }) { return [] }
            return languages.filter { typed.isEmpty || $0.lowercased().hasPrefix(typed) }
                .prefix(limit).map { complete("lang:\($0.lowercased())", "Language: \(languageName($0))") }
        }
        if let typed = value(ofPartial: partial, prefixes: ["#", "tag:"]) {
            if categories.contains(where: { $0.lowercased() == typed }) { return [] }
            return categories.filter { typed.isEmpty || $0.lowercased().hasPrefix(typed) }
                .prefix(limit).map { complete("#\($0.lowercased())", "Tag: \($0)") }
        }
        if partial.hasPrefix("is:") || partial.isEmpty {
            let filters = [("lang:", "Filter by language (lang:)"), ("#", "Filter by tag (#)"),
                           ("is:pinned", "Pinned only (is:pinned)"), ("is:favorite", "Favorites only (is:favorite)")]
            return filters.filter { partial.isEmpty || $0.0.hasPrefix(partial) }.map { token, title in
                // A bare `lang:` or `#` waits for a value, so no trailing space.
                let done = token.hasPrefix("is:")
                return SearchSuggestion(title: title, completion: prefix + token + (done ? " " : ""))
            }
        }
        return []
    }

    private static func value(ofPartial token: String, prefixes: [String]) -> String? {
        prefixes.first { token.hasPrefix($0) }.map { String(token.dropFirst($0.count)) }
    }
}
