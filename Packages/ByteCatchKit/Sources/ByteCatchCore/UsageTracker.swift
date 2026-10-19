import Foundation

/// Counts how often each snippet is copied, per server, on this device only (App Group defaults,
/// so widgets count too). Powers "Most Used".
public struct UsageTracker: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppEnvironment.sharedDefaults) {
        self.defaults = defaults
    }

    private func key(_ server: ServerURL) -> String { "usage." + server.cacheKey }

    /// id → [count, last copied (seconds since 1970)]
    private func table(_ server: ServerURL) -> [String: [Double]] {
        defaults.dictionary(forKey: key(server)) as? [String: [Double]] ?? [:]
    }

    public func recordCopy(snippetID: Int, server: ServerURL, at date: Date = Date()) {
        var t = table(server)
        let entry = t[String(snippetID)] ?? [0, 0]
        t[String(snippetID)] = [entry[0] + 1, date.timeIntervalSince1970]
        defaults.set(t, forKey: key(server))
    }

    public func count(snippetID: Int, server: ServerURL) -> Int {
        Int(table(server)[String(snippetID)]?.first ?? 0)
    }

    /// Most copied first; ties go to the most recently copied.
    public func mostUsed(server: ServerURL, limit: Int) -> [Int] {
        table(server)
            .compactMap { id, v in Int(id).map { ($0, v[0], v.count > 1 ? v[1] : 0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }
            .prefix(limit).map(\.0)
    }

    public func forget(snippetID: Int, server: ServerURL) {
        var t = table(server)
        t[String(snippetID)] = nil
        defaults.set(t, forKey: key(server))
    }
}
