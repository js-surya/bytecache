import Foundation

/// The order of pinned snippets, per server. ByteStash only stores whether a snippet is pinned, so
/// ByteCache keeps the order itself (CP-99). Pins not in the order (new ones) go first.
public struct PinOrders: Codable, Equatable, Sendable {
    public private(set) var ids: [String: [Int]]

    public init(_ ids: [String: [Int]] = [:]) {
        self.ids = ids
    }

    public func order(server: ServerURL) -> [Int] { ids[server.cacheKey] ?? [] }

    public mutating func set(_ order: [Int], server: ServerURL) {
        ids[server.cacheKey] = order.isEmpty ? nil : order
    }

    /// The whole order after moving rows of `visible` (the pins a list shows, in its order): those pins
    /// trade places among themselves, and pins the list doesn't show (filtered out) keep theirs.
    public static func moving(_ visible: [Int], in stored: [Int], from source: IndexSet, to destination: Int) -> [Int] {
        let shown = Set(visible)
        // Pins without a place yet are shown first; give them theirs.
        let before = visible.filter { !stored.contains($0) } + stored
        var reordered = moved(visible, from: source, to: destination).makeIterator()
        return before.map { shown.contains($0) ? reordered.next() ?? $0 : $0 }
    }

    /// Drops a snippet that's no longer pinned.
    public mutating func remove(_ id: Int, server: ServerURL) {
        set(order(server: server).filter { $0 != id }, server: server)
    }

    /// The pinned snippets in `pinned` after moving `source` to `destination` (as SwiftUI's `onMove`
    /// gives them), as the order to keep.
    public static func moved(_ pinned: [Int], from source: IndexSet, to destination: Int) -> [Int] {
        let moving = source.sorted().filter(pinned.indices.contains).map { pinned[$0] }
        var rest = pinned
        for index in source.sorted(by: >) where rest.indices.contains(index) { rest.remove(at: index) }
        let before = source.filter { $0 < destination }.count
        let insertAt = min(max(destination - before, 0), rest.count)
        rest.insert(contentsOf: moving, at: insertAt)
        return rest
    }
}
