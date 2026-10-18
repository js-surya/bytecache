import Foundation

public struct FragmentDraft: Encodable, Equatable, Sendable {
    public var fileName: String
    public var code: String
    public var language: String

    public init(fileName: String, code: String, language: String) {
        self.fileName = fileName
        self.code = code
        self.language = language
    }

    private enum CodingKeys: String, CodingKey {
        case fileName = "file_name", code, language
    }
}

/// Body for `POST /api/snippets` and `PUT /api/snippets/:id`.
/// PUT replaces everything, so a draft always carries every field including `is_public`.
public struct SnippetDraft: Encodable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var categories: [String]
    public var fragments: [FragmentDraft]
    public var isPublic: Bool

    public init(
        title: String, description: String = "", categories: [String] = [],
        fragments: [FragmentDraft], isPublic: Bool = false
    ) {
        self.title = title
        self.description = description
        self.categories = categories
        self.fragments = fragments
        self.isPublic = isPublic
    }

    /// Starts an edit from an existing snippet, keeping every field the PUT would otherwise reset.
    public init(from snippet: Snippet) {
        self.init(
            title: snippet.title,
            description: snippet.description,
            categories: snippet.categories,
            fragments: snippet.fragments
                .sorted { $0.position < $1.position }
                .map { FragmentDraft(fileName: $0.fileName, code: $0.code, language: $0.language) },
            isPublic: snippet.isPublic
        )
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, categories, fragments, isPublic = "is_public"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(categories, forKey: .categories)
        try c.encode(fragments, forKey: .fragments)
        try c.encode(isPublic ? 1 : 0, forKey: .isPublic)
    }
}
