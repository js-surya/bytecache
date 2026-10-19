import Foundation

/// An API key as listed by `GET /api/keys` (the secret itself is only returned once, on creation).
public struct APIKeyInfo: Decodable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let createdAt: Date?
    public let lastUsedAt: Date?
    public let isActive: Bool

    public init(id: Int, name: String, createdAt: Date?, lastUsedAt: Date?, isActive: Bool) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isActive = isActive
    }

    private enum CodingKeys: String, CodingKey { case id, name, createdAt, lastUsedAt, isActive }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(Int.self, forKey: .id),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            createdAt: try? c.decodeIfPresent(Date.self, forKey: .createdAt),
            lastUsedAt: try? c.decodeIfPresent(Date.self, forKey: .lastUsedAt),
            isActive: try c.decodeIfPresent(FlexibleBool.self, forKey: .isActive)?.wrappedValue ?? true
        )
    }
}

/// `POST /api/keys` response: the key's details plus the secret, shown to the user once.
public struct CreatedAPIKey: Decodable, Equatable, Sendable {
    public let info: APIKeyInfo
    public let key: String

    private enum CodingKeys: String, CodingKey { case key }

    public init(from decoder: any Decoder) throws {
        info = try APIKeyInfo(from: decoder)
        key = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .key)
    }
}
