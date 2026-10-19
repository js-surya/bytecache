import Foundation

/// One page of `GET /api/snippets`, decoded from `{ data, pagination }`.
public struct SnippetPage: Decodable, Sendable {
    public let snippets: [Snippet]
    public let total: Int
    public let offset: Int
    public let limit: Int
    public let hasMore: Bool

    private enum CodingKeys: String, CodingKey { case data, pagination }
    private struct Pagination: Decodable {
        let total: Int
        let offset: Int
        let limit: Int
        let hasMore: Bool
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let p = try c.decode(Pagination.self, forKey: .pagination)
        snippets = try c.decode([Snippet].self, forKey: .data)
        total = p.total
        offset = p.offset
        limit = p.limit
        hasMore = p.hasMore
    }
}
