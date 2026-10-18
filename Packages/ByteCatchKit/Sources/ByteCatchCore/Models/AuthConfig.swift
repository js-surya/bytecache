import Foundation

/// `GET /api/auth/config`.
public struct AuthConfig: Decodable, Sendable {
    public let authRequired: Bool
    public let allowNewAccounts: Bool
    public let hasUsers: Bool
    public let disableAccounts: Bool
    public let disableInternalAccounts: Bool
}
