import Foundation

public struct Snippet: Codable, Identifiable, Hashable, Sendable {
    public var id: Int
    public var title: String
    public var description: String
    public var updatedAt: Date?
    public var expiryDate: Date?
    public var isPublic: Bool
    public var isPinned: Bool
    public var isFavorite: Bool
    public var categories: [String]
    public var fragments: [Fragment]
    public var shareCount: Int
    /// Owner, as sent with public snippets.
    public var username: String?

    public init(
        id: Int, title: String, description: String, updatedAt: Date?, expiryDate: Date?,
        isPublic: Bool, isPinned: Bool, isFavorite: Bool, categories: [String],
        fragments: [Fragment], shareCount: Int, username: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.updatedAt = updatedAt
        self.expiryDate = expiryDate
        self.isPublic = isPublic
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.categories = categories
        self.fragments = fragments
        self.shareCount = shareCount
        self.username = username
    }
}

extension Snippet {
    private enum CodingKeys: String, CodingKey {
        case id, title, description, updatedAt, expiryDate, isPublic, isPinned, isFavorite
        case categories, fragments, shareCount, username
    }

    /// Tolerant decoding: booleans may be `0/1` ints, and optional fields may be absent.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) throws -> Bool {
            try c.decodeIfPresent(FlexibleBool.self, forKey: key)?.wrappedValue ?? false
        }
        self.init(
            id: try c.decode(Int.self, forKey: .id),
            title: try c.decode(String.self, forKey: .title),
            description: try c.decodeIfPresent(String.self, forKey: .description) ?? "",
            updatedAt: try c.decodeIfPresent(Date.self, forKey: .updatedAt),
            expiryDate: try c.decodeIfPresent(Date.self, forKey: .expiryDate),
            isPublic: try flag(.isPublic),
            isPinned: try flag(.isPinned),
            isFavorite: try flag(.isFavorite),
            categories: try c.decodeIfPresent([String].self, forKey: .categories) ?? [],
            fragments: try c.decodeIfPresent([Fragment].self, forKey: .fragments) ?? [],
            shareCount: try c.decodeIfPresent(Int.self, forKey: .shareCount) ?? 0,
            username: try c.decodeIfPresent(String.self, forKey: .username)
        )
    }
}
