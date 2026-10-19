import Foundation

public enum SnippetSort: String, Sendable {
    case newest
    case oldest
    case alphaAsc = "alpha-asc"
    case alphaDesc = "alpha-desc"
}

/// Parameters for `GET /api/snippets`.
public struct SnippetQuery: Equatable, Sendable {
    public var search: String?
    public var searchCode = false
    public var language: String?
    public var categories: [String] = []
    public var favorites = false
    public var pinned = false
    public var recycled = false
    public var sort = SnippetSort.newest
    public var limit = 50
    public var offset = 0

    public init(
        search: String? = nil, searchCode: Bool = false, language: String? = nil,
        categories: [String] = [], favorites: Bool = false, pinned: Bool = false,
        recycled: Bool = false, sort: SnippetSort = .newest, limit: Int = 50, offset: Int = 0
    ) {
        self.search = search
        self.searchCode = searchCode
        self.language = language
        self.categories = categories
        self.favorites = favorites
        self.pinned = pinned
        self.recycled = recycled
        self.sort = sort
        self.limit = limit
        self.offset = offset
    }

    /// Query items for the request; false and empty options are omitted.
    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let search, !search.isEmpty { items.append(.init(name: "search", value: search)) }
        if searchCode { items.append(.init(name: "searchCode", value: "true")) }
        if let language, !language.isEmpty { items.append(.init(name: "language", value: language)) }
        if !categories.isEmpty {
            items.append(.init(name: "category", value: categories.map { $0.lowercased() }.joined(separator: ",")))
        }
        if favorites { items.append(.init(name: "favorites", value: "true")) }
        if pinned { items.append(.init(name: "pinned", value: "true")) }
        if recycled { items.append(.init(name: "recycled", value: "true")) }
        items.append(.init(name: "sort", value: sort.rawValue))
        items.append(.init(name: "limit", value: String(limit)))
        items.append(.init(name: "offset", value: String(offset)))
        return items
    }
}
