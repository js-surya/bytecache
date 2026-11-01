import Foundation

/// The one seam between the API client and the network, so tests can stub responses.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

extension URLSession {
    /// For ByteStash servers. ByteCache signs every request with its `bytestashauth` header; since
    /// ByteStash 1.6.0 logins also set an HttpOnly `bytestash_token` cookie for the website, which
    /// ByteCache mustn't keep: after signing out it would still sign requests in. No cookies are
    /// stored or sent.
    public static let byteStash: URLSession = URLSession(configuration: byteStashConfiguration)

    static var byteStashConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return configuration
    }
}

/// Cookies earlier builds kept from ByteStash 1.6 logins in the app's shared cookie store.
public enum ByteStashCookies {
    static let names: Set<String> = ["bytestash_token", "bytestash_id_token"]

    public static func removeLeftovers(from storage: HTTPCookieStorage = .shared) {
        for cookie in storage.cookies ?? [] where names.contains(cookie.name) {
            storage.deleteCookie(cookie)
        }
    }
}
