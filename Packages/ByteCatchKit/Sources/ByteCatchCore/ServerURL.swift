import Foundation

/// A normalized ByteStash server base URL (may include a sub-path such as `/bytestash`).
public struct ServerURL: Hashable, Codable, Sendable {
    public let base: URL

    /// Accepts loosely typed input: missing scheme, trailing `/`, or a pasted URL ending in `/api` or `/login`.
    public init(_ raw: String) throws(APIError) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .invalidServerURL }
        if !text.contains("://") { text = "https://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { throw .invalidServerURL }

        var segments = components.path.split(separator: "/").map(String.init)
        if let last = segments.last, last == "api" || last == "login" {
            segments.removeLast()
        }

        components.scheme = scheme
        components.host = host.lowercased()
        components.query = nil
        components.fragment = nil
        components.path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")

        guard let url = components.url else { throw .invalidServerURL }
        base = url
    }

    /// Full URL for an API path such as `/api/snippets`, without doubled slashes.
    public func endpoint(_ path: String) -> URL {
        let trimmed = path.drop { $0 == "/" }
        return URL(string: base.absoluteString + "/" + trimmed) ?? base
    }

    /// Stable key identifying this server, e.g. for per-server caches.
    public var cacheKey: String { base.absoluteString }
}
