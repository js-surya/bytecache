import Foundation

/// Errors surfaced by the ByteStash client. Extended as the API client grows.
public enum APIError: Error, Equatable, Sendable {
    /// The server address could not be turned into an http(s) base URL.
    case invalidServerURL
}
