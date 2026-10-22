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
