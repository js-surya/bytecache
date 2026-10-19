import Foundation

/// A ByteStash share link (`<server>/s/<id>`), as listed by `GET /api/share/snippet/:id`.
public struct ShareLink: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let requiresAuth: Bool
    public let expiresAt: Date?
    public let createdAt: Date?
    public let expired: Bool

    public init(id: String, requiresAuth: Bool, expiresAt: Date?, createdAt: Date?, expired: Bool) {
        self.id = id
        self.requiresAuth = requiresAuth
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.expired = expired
    }

    private enum CodingKeys: String, CodingKey { case id, requiresAuth, expiresAt, createdAt, expired }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            requiresAuth: try c.decodeIfPresent(FlexibleBool.self, forKey: .requiresAuth)?.wrappedValue ?? false,
            expiresAt: try? c.decodeIfPresent(Date.self, forKey: .expiresAt),
            createdAt: try? c.decodeIfPresent(Date.self, forKey: .createdAt),
            expired: try c.decodeIfPresent(FlexibleBool.self, forKey: .expired)?.wrappedValue ?? false
        )
    }

    public static func url(id: String, server: ServerURL) -> URL {
        server.endpoint("/s/\(id)")
    }
}

struct CreateShareBody: Encodable {
    let snippetId: Int
    let requiresAuth: Bool
    let expiresIn: Int?
}

struct CreatedShare: Decodable {
    let id: String
}
