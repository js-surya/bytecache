import Foundation

/// Errors surfaced by the ByteStash client.
public enum APIError: Error, Equatable, Sendable {
    /// The server address could not be turned into a usable http(s) base URL.
    case invalidServer
    /// 401: missing, expired or revoked token, or bad credentials.
    case unauthorized
    /// 403: for example a disabled account. Carries the server's message when there is one.
    case forbidden(String?)
    case notFound
    case server(status: Int, message: String?)
    /// The request never reached the server (no network, timeout, host unreachable).
    case offline
    case decoding(String)
    /// The address answered, but not like a ByteStash server (for example an HTML page).
    case notByteStash
    /// Another saved server already uses that address.
    case duplicateServer
}
