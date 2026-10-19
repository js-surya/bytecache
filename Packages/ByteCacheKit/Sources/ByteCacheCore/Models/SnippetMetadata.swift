import Foundation

/// `GET /api/snippets/metadata`.
public struct SnippetMetadata: Decodable, Sendable {
    public let categories: [String]
    public let languages: [String]
}
