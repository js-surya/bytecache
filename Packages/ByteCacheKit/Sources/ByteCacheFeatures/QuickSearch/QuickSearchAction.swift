import Foundation

/// What choosing a snippet in Quick Search or the menu bar does (CP-68).
public enum QuickSearchAction: String, CaseIterable, Identifiable, Sendable {
    case copy, paste, open

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .copy: "Copy to Clipboard"
        case .paste: "Paste into Active App"
        case .open: "Open in ByteCache"
        }
    }

    private var verb: String {
        switch self {
        case .copy: "copies"
        case .paste: "pastes"
        case .open: "opens"
        }
    }

    /// ⌘Return always opens; ⌥Return and Return do what Settings say.
    @MainActor
    public static func forReturn(option: Bool, command: Bool, settings: AppSettings) -> QuickSearchAction {
        if command { return .open }
        return option ? settings.quickSearchOptionReturnAction : settings.quickSearchReturnAction
    }

    /// The key line under the results, e.g. "Return copies · ⌥Return pastes · ⌘Return opens · Esc closes".
    @MainActor
    public static func hint(settings: AppSettings) -> String {
        var parts = ["Return \(settings.quickSearchReturnAction.verb)"]
        let option = settings.quickSearchOptionReturnAction
        if option != settings.quickSearchReturnAction && option != .open { parts.append("⌥Return \(option.verb)") }
        if settings.quickSearchReturnAction != .open { parts.append("⌘Return opens") }
        parts.append("Esc closes")
        return parts.joined(separator: " · ")
    }
}

/// What Quick Search and the menu bar list before anything is typed (CP-69).
public enum QuickSearchStart: Hashable, Sendable, Identifiable {
    case recent, pinned, favorites
    case smartGroup(UUID)

    public var id: String { rawValue }

    public var rawValue: String {
        switch self {
        case .recent: "recent"
        case .pinned: "pinned"
        case .favorites: "favorites"
        case .smartGroup(let id): "group:\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "recent": self = .recent
        case "pinned": self = .pinned
        case "favorites": self = .favorites
        default:
            guard rawValue.hasPrefix("group:"), let id = UUID(uuidString: String(rawValue.dropFirst(6))) else { return nil }
            self = .smartGroup(id)
        }
    }

    /// The list it shows; Recent is All Snippets, newest first.
    public var sidebarItem: SidebarItem {
        switch self {
        case .recent: .all
        case .pinned: .pinned
        case .favorites: .favorites
        case .smartGroup(let id): .smartGroup(id)
        }
    }
}

/// The menu bar window's size.
public enum MenuBarPanelSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    public var size: CGSize {
        switch self {
        case .small: CGSize(width: 420, height: 440)
        case .medium: CGSize(width: 520, height: 540)
        case .large: CGSize(width: 640, height: 660)
        }
    }
}
