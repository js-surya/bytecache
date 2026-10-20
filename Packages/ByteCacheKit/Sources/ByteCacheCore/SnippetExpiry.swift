import Foundation

/// When snippets expire. ByteStash doesn't store an expiry date, so ByteCache keeps them
/// (per server and snippet) and moves expired snippets to the Recycle Bin itself.
public struct SnippetExpiries: Codable, Equatable, Sendable {
    public private(set) var dates: [String: Date]

    public init(_ dates: [String: Date] = [:]) {
        self.dates = dates
    }

    static func key(_ server: ServerURL, _ id: Int) -> String { "\(server.cacheKey)#\(id)" }

    public func date(snippetID id: Int, server: ServerURL) -> Date? {
        dates[Self.key(server, id)]
    }

    public mutating func set(_ date: Date?, snippetID id: Int, server: ServerURL) {
        dates[Self.key(server, id)] = date
    }

    /// Snippets on `server` whose time has run out.
    public func due(server: ServerURL, now: Date = Date()) -> [Int] {
        let prefix = server.cacheKey + "#"
        return dates.compactMap { key, date in
            guard key.hasPrefix(prefix), date <= now else { return nil }
            return Int(key.dropFirst(prefix.count))
        }.sorted()
    }
}

/// Countdown text: "Expired", "Expires in 45s", "Expires in 12m", "Expires in 3h 12m", "Expires in 2d 4h".
public enum ExpiryText {
    public static func remaining(until date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded(.down))
        guard seconds > 0 else { return "Expired" }
        let days = seconds / 86_400, hours = seconds % 86_400 / 3600, minutes = seconds % 3600 / 60
        if days > 0 { return "Expires in \(days)d" + (hours > 0 ? " \(hours)h" : "") }
        if hours > 0 { return "Expires in \(hours)h" + (minutes > 0 ? " \(minutes)m" : "") }
        if minutes > 0 { return "Expires in \(minutes)m" }
        return "Expires in \(seconds)s"
    }

    /// The last hour counts down every second and is shown as urgent.
    public static func isSoon(_ date: Date, now: Date = Date()) -> Bool {
        date.timeIntervalSince(now) < 3600
    }
}

/// The choices in the editor.
public enum ExpiryChoice: Hashable, Sendable {
    case never, hour, day, week, month
    case date(Date)

    public static let presets: [ExpiryChoice] = [.never, .hour, .day, .week, .month]

    public var title: String {
        switch self {
        case .never: "Never"
        case .hour: "In 1 Hour"
        case .day: "In 1 Day"
        case .week: "In 1 Week"
        case .month: "In 1 Month"
        case .date: "On a Date"
        }
    }

    /// The expiry date this choice means, counted from `now`.
    public func date(from now: Date = Date()) -> Date? {
        switch self {
        case .never: nil
        case .hour: now.addingTimeInterval(3600)
        case .day: now.addingTimeInterval(86_400)
        case .week: now.addingTimeInterval(7 * 86_400)
        case .month: Calendar.current.date(byAdding: .month, value: 1, to: now)
        case .date(let date): date
        }
    }
}
