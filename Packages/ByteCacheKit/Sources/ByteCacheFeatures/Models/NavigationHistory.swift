import Foundation

/// Back / Forward through the sections and snippets you looked at (CP-71), like a browser.
public struct NavigationHistory: Sendable {
    public struct Entry: Hashable, Sendable {
        public var section: SidebarItem
        public var snippet: Int?

        public init(section: SidebarItem, snippet: Int?) {
            self.section = section
            self.snippet = snippet
        }
    }

    static let limit = 100

    private var entries: [Entry]
    private var index = 0

    public init(start: SidebarItem) {
        entries = [Entry(section: start, snippet: nil)]
    }

    public var current: Entry { entries[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index < entries.count - 1 }

    /// A section was picked. Picking the section you're already in (also while going back) records nothing.
    public mutating func visit(section: SidebarItem) {
        guard section != current.section else { return }
        push(Entry(section: section, snippet: nil))
    }

    /// A snippet was opened in the current section. It fills in the section's entry when that has no
    /// snippet yet; clearing the selection isn't a place to go back to.
    public mutating func visit(snippet: Int?) {
        guard let snippet, snippet != current.snippet else { return }
        if current.snippet == nil {
            entries[index].snippet = snippet
            entries.removeSubrange((index + 1)...)
        } else {
            push(Entry(section: current.section, snippet: snippet))
        }
    }

    /// The entry to show, or nil at the start. Showing it must go through `visit`, which then records nothing.
    public mutating func back() -> Entry? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    public mutating func forward() -> Entry? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }

    private mutating func push(_ entry: Entry) {
        entries.removeSubrange((index + 1)...)
        entries.append(entry)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        index = entries.count - 1
    }
}
