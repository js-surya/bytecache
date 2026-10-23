import os
import SwiftUI

extension EnvironmentValues {
    /// The id of this window's customisable toolbar (`.toolbar(id:)`). See `WindowToolbarID`.
    @Entry public var windowToolbarID = "main"
}

/// A toolbar id of its own for each Mac window.
///
/// AppKit keeps toolbars with the same id in sync across windows, and throws when one window inserts
/// an item another window can't provide. Ours differ from window to window (the snippet actions only
/// exist while a snippet is open), so a second window crashed the app (CP-82). The first window keeps
/// the plain id, so its customised layout stays; others get "main-2", "main-3"…, reused once closed,
/// so their customisations don't pile up. iPad has no toolbar syncing, so every window there uses
/// the plain id.
@MainActor @Observable
public final class WindowToolbarID {
    public let id: String
    @ObservationIgnored private let base: String
    @ObservationIgnored private let number: Int

    private nonisolated static let inUse = OSAllocatedUnfairLock(initialState: [String: Set<Int>]())

    public init(base: String) {
        self.base = base
        #if os(macOS)
        number = Self.inUse.withLock { used in
            let number = (1...).first { !used[base, default: []].contains($0) }!
            used[base, default: []].insert(number)
            return number
        }
        #else
        number = 1
        #endif
        id = number == 1 ? base : "\(base)-\(number)"
    }

    isolated deinit {
        #if os(macOS)
        let base = base, number = number
        Self.inUse.withLock { _ = $0[base]?.remove(number) }
        #endif
    }

    #if DEBUG
    /// Number of ids in use for `base` (tests).
    nonisolated static func count(base: String) -> Int {
        inUse.withLock { $0[base]?.count ?? 0 }
    }
    #endif
}
