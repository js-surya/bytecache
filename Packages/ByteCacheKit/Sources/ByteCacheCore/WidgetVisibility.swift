import Foundation

/// The user's choice for widgets while App Lock is on (Settings → App Lock).
public enum WidgetLockMode: String, CaseIterable, Identifiable, Sendable {
    case hideAll, titlesOnly, showAll

    public static let defaultsKey = "widgetsWhileLocked"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hideAll: "Hide Everything"
        case .titlesOnly: "Titles Only"
        case .showAll: "Show Everything"
        }
    }

    /// Titles only unless the user picked something else: titles are rarely secret, code often is.
    public static func stored(in defaults: UserDefaults = AppEnvironment.sharedDefaults) -> WidgetLockMode {
        defaults.string(forKey: defaultsKey).flatMap(WidgetLockMode.init(rawValue:)) ?? .titlesOnly
    }
}

/// What a widget may show right now.
public enum WidgetVisibility: Equatable, Sendable {
    case everything, titlesOnly, hidden

    /// Copying puts code on the clipboard, so only widgets that show the code may do it.
    public var allowsCopy: Bool { self == .everything }

    public static func resolve(appLockEnabled: Bool, mode: WidgetLockMode) -> WidgetVisibility {
        guard appLockEnabled else { return .everything }
        switch mode {
        case .hideAll: return .hidden
        case .titlesOnly: return .titlesOnly
        case .showAll: return .everything
        }
    }

    public static func current(in defaults: UserDefaults = AppEnvironment.sharedDefaults) -> WidgetVisibility {
        resolve(appLockEnabled: defaults.bool(forKey: AppEnvironment.appLockEnabledKey), mode: WidgetLockMode.stored(in: defaults))
    }
}
