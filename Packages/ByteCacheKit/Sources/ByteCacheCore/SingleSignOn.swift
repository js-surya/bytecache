import Foundation

/// `GET /api/auth/oidc/config`: whether the server offers single sign-on, and its button title.
public struct SSOConfig: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let displayName: String?

    public init(enabled: Bool, displayName: String? = nil) {
        self.enabled = enabled
        self.displayName = displayName
    }

    /// "Sign in with Authentik"; the server's default name is "Single Sign-On".
    public var buttonTitle: String {
        let name = displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty || name == "Single Sign-On" ? "Sign In with Single Sign-On" : "Sign In with \(name)"
    }
}

/// Reads where ByteStash's single sign-on flow has got to (CP-72). The app opens `/api/auth/oidc/auth`
/// in a sign-in web view; the identity provider returns to the server, which sets the login as the
/// `bytestash_token` cookie and goes on to `/auth/callback`, or to `/login?error=…` when it failed.
public enum SingleSignOn {
    public static let tokenCookie = "bytestash_token"

    public enum Step: Equatable, Sendable {
        /// Signed in: read the token cookie.
        case finished
        case failed(String)
    }

    public static func startURL(for server: ServerURL) -> URL {
        server.endpoint("/api/auth/oidc/auth")
    }

    /// The step a page load means, or nil while the sign-in is still going (provider pages and so on).
    public static func step(for url: URL, server: ServerURL) -> Step? {
        guard url.host()?.lowercased() == server.base.host()?.lowercased() else { return nil }
        let path = url.path()
        if path.hasSuffix("/auth/callback"), !path.contains("/api/") { return .finished }
        guard path.hasSuffix("/login"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let error = items.first(where: { $0.name == "error" })?.value else { return nil }
        let detail = items.first { $0.name == "message" }?.value
        return .failed(message(for: error, detail: detail))
    }

    static func message(for error: String, detail: String?) -> String {
        switch error {
        case "registration_disabled": return "This server doesn't allow new accounts, so it can't create one for this sign-in."
        case "account_deactivated": return detail ?? "Your account on this server has been deactivated."
        case "config_error": return "Single sign-on isn't set up correctly on this server."
        case "provider_error": return detail ?? "The sign-in provider refused the sign-in."
        default: return detail ?? "Single sign-on didn't work. Try again."
        }
    }
}
