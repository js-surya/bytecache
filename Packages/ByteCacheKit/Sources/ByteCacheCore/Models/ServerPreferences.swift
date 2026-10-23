import Foundation

/// The per-user preferences ByteStash keeps on the server (`/api/settings`, ByteStash 1.5.13+) that
/// ByteCache has too (CP-74). Other keys (view mode, locale…) belong to the web app and are left alone.
public struct ServerPreferences: Codable, Equatable, Sendable {
    /// "light", "dark" or "system".
    public var theme: String?
    public var showLineNumbers: Bool?
    public var includeCodeInSearch: Bool?

    public init(theme: String? = nil, showLineNumbers: Bool? = nil, includeCodeInSearch: Bool? = nil) {
        self.theme = theme
        self.showLineNumbers = showLineNumbers
        self.includeCodeInSearch = includeCodeInSearch
    }

    public var isEmpty: Bool { theme == nil && showLineNumbers == nil && includeCodeInSearch == nil }
}

/// `{"settings": {...}}`, both what the server answers and what PATCH sends.
struct ServerPreferencesResponse: Codable {
    var settings: ServerPreferences
}
