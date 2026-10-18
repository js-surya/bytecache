import Foundation

public struct User: Codable, Sendable {
    public let id: Int
    public let username: String
    public let isAdmin: Bool

    public init(id: Int, username: String, isAdmin: Bool = false) {
        self.id = id
        self.username = username
        self.isAdmin = isAdmin
    }

    private enum CodingKeys: String, CodingKey { case id, username, isAdmin }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        isAdmin = try c.decodeIfPresent(FlexibleBool.self, forKey: .isAdmin)?.wrappedValue ?? false
    }
}
