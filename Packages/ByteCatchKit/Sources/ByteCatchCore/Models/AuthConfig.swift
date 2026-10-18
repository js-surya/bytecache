import Foundation

/// `GET /api/auth/config`.
public struct AuthConfig: Decodable, Equatable, Sendable {
    public let authRequired: Bool
    public let allowNewAccounts: Bool
    public let hasUsers: Bool
    public let disableAccounts: Bool
    public let disableInternalAccounts: Bool

    public init(
        authRequired: Bool = true, allowNewAccounts: Bool = false, hasUsers: Bool = true,
        disableAccounts: Bool = false, disableInternalAccounts: Bool = false
    ) {
        self.authRequired = authRequired
        self.allowNewAccounts = allowNewAccounts
        self.hasUsers = hasUsers
        self.disableAccounts = disableAccounts
        self.disableInternalAccounts = disableInternalAccounts
    }
}

extension AuthConfig {
    private enum CodingKeys: String, CodingKey {
        case authRequired, allowNewAccounts, hasUsers, disableAccounts, disableInternalAccounts
    }

    /// Tolerant decoding: older or single-user servers may omit flags, so each falls back to its default.
    /// `authRequired` is mandatory — it is what tells a ByteStash config apart from any other JSON.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AuthConfig()
        self.init(
            authRequired: try c.decode(Bool.self, forKey: .authRequired),
            allowNewAccounts: try c.decodeIfPresent(Bool.self, forKey: .allowNewAccounts) ?? defaults.allowNewAccounts,
            hasUsers: try c.decodeIfPresent(Bool.self, forKey: .hasUsers) ?? defaults.hasUsers,
            disableAccounts: try c.decodeIfPresent(Bool.self, forKey: .disableAccounts) ?? defaults.disableAccounts,
            disableInternalAccounts: try c.decodeIfPresent(Bool.self, forKey: .disableInternalAccounts) ?? defaults.disableInternalAccounts
        )
    }
}
