import Foundation

public struct User: Codable, Equatable, Sendable {
    public let id: Int
    public let username: String
    public let isAdmin: Bool
    /// The single sign-on identity (`oidc_id`, sent by ByteStash 1.6.1+ from `/verify`): such accounts
    /// have no password to change.
    public let oidcID: String?

    public var usesSingleSignOn: Bool { oidcID != nil }

    public init(id: Int, username: String, isAdmin: Bool = false, oidcID: String? = nil) {
        self.id = id
        self.username = username
        self.isAdmin = isAdmin
        self.oidcID = oidcID
    }

    /// The same user, marked as signed in with single sign-on (servers before 1.6.1 don't say).
    public func signedInWithSingleSignOn() -> User {
        usesSingleSignOn ? self : User(id: id, username: username, isAdmin: isAdmin, oidcID: "")
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, isAdmin
        case oidcID = "oidc_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        isAdmin = try c.decodeIfPresent(FlexibleBool.self, forKey: .isAdmin)?.wrappedValue ?? false
        // A string from most providers; tolerate a number.
        oidcID = (try? c.decodeIfPresent(String.self, forKey: .oidcID))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .oidcID)).flatMap { $0.map(String.init) }
    }
}
