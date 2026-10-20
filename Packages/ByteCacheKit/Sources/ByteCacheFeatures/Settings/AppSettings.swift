import ByteCacheCore
import Observation
import SwiftUI

public enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, light, dark
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public enum IconStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case sfSymbols, lucide
    public var id: String { rawValue }
    public var title: String { self == .sfSymbols ? "SF Symbols" : "Lucide" }
}

public enum AccentChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal, indigo, graphite
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    public var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .indigo: .indigo
        case .graphite: .gray
        }
    }
}

/// Display preferences. Stored in the App Group defaults so the share extension looks the same.
@MainActor @Observable
public final class AppSettings {
    public static let fontSizes = 10.0...24.0

    public var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    public var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: Key.accent) } }
    public var codeThemeID: String { didSet { defaults.set(codeThemeID, forKey: Key.codeThemeID) } }
    public var iconStyle: IconStyle { didSet { defaults.set(iconStyle.rawValue, forKey: Key.iconStyle) } }
    /// Language logos in their brand colours or tinted like the other icons.
    public var languageIconStyle: LanguageIconStyle {
        didSet { defaults.set(languageIconStyle.rawValue, forKey: Key.languageIconStyle) }
    }
    /// Search matches code as well as titles and descriptions.
    public var searchInCode: Bool { didSet { defaults.set(searchInCode, forKey: Key.searchInCode) } }
    public var showLineNumbers: Bool { didSet { defaults.set(showLineNumbers, forKey: Key.lineNumbers) } }
    /// Long lines wrap in the code view instead of scrolling sideways.
    public var wrapLines: Bool { didSet { defaults.set(wrapLines, forKey: Key.wrapLines) } }
    /// Saved rule-based groups, shown in the sidebar.
    public var smartGroups: [SmartGroup] {
        didSet { defaults.set(try? JSONEncoder().encode(smartGroups), forKey: Key.smartGroups) }
    }
    /// Device-only switches (never synced themselves).
    public var iCloudSyncEnabled: Bool { didSet { defaults.set(iCloudSyncEnabled, forKey: Key.iCloudSync) } }
    public var handoffEnabled: Bool { didSet { defaults.set(handoffEnabled, forKey: Key.handoff) } }
    public var suggestionsEnabled: Bool { didSet { defaults.set(suggestionsEnabled, forKey: Key.suggestions) } }
    /// Device-only: whether to look for new releases on GitHub once a day.
    public var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: Key.checkForUpdates) } }
    /// Device-only: phones differ, so haptics aren't synced.
    public var hapticsEnabled: Bool {
        didSet {
            defaults.set(hapticsEnabled, forKey: Key.haptics)
            Haptics.configure(enabled: hapticsEnabled, strength: hapticStrength)
        }
    }
    public var hapticStrength: HapticStrength {
        didSet {
            defaults.set(hapticStrength.rawValue, forKey: Key.hapticStrength)
            Haptics.configure(enabled: hapticsEnabled, strength: hapticStrength)
        }
    }
    public var codeFontSize: Double {
        didSet {
            let clamped = min(max(codeFontSize, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
            if clamped != codeFontSize { codeFontSize = clamped }
            defaults.set(codeFontSize, forKey: Key.fontSize)
        }
    }

    public var codeTheme: CodeTheme {
        CodeTheme.named(codeThemeID) ?? CodeTheme.named(CodeTheme.defaultID)!
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let appearance = "appearance", accent = "accent", codeThemeID = "codeThemeID", iconStyle = "iconStyle", searchInCode = "searchInCode"
        static let languageIconStyle = "languageIconStyle"
        static let fontSize = "codeFontSize", lineNumbers = "showLineNumbers", wrapLines = "wrapLines", smartGroups = "smartGroups"
        static let iCloudSync = "iCloudSyncEnabled", handoff = "handoffEnabled", suggestions = "suggestionsEnabled"
        static let haptics = "hapticsEnabled", hapticStrength = "hapticStrength"
        static let checkForUpdates = "checkForUpdates"
    }

    public init(defaults: UserDefaults = AppEnvironment.sharedDefaults) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init) ?? .system
        accent = defaults.string(forKey: Key.accent).flatMap(AccentChoice.init) ?? .blue
        iconStyle = defaults.string(forKey: Key.iconStyle).flatMap(IconStyle.init) ?? .sfSymbols
        languageIconStyle = defaults.string(forKey: Key.languageIconStyle).flatMap(LanguageIconStyle.init) ?? .color
        searchInCode = defaults.bool(forKey: Key.searchInCode)
        let storedTheme = defaults.string(forKey: Key.codeThemeID) ?? CodeTheme.defaultID
        codeThemeID = CodeTheme.named(storedTheme) == nil ? CodeTheme.defaultID : storedTheme
        let size = defaults.object(forKey: Key.fontSize) as? Double ?? 14
        codeFontSize = min(max(size, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        showLineNumbers = defaults.object(forKey: Key.lineNumbers) as? Bool ?? true
        wrapLines = defaults.bool(forKey: Key.wrapLines)
        smartGroups = defaults.data(forKey: Key.smartGroups).flatMap { try? JSONDecoder().decode([SmartGroup].self, from: $0) } ?? []
        iCloudSyncEnabled = defaults.object(forKey: Key.iCloudSync) as? Bool ?? true
        handoffEnabled = defaults.object(forKey: Key.handoff) as? Bool ?? true
        suggestionsEnabled = defaults.object(forKey: Key.suggestions) as? Bool ?? true
        checkForUpdates = defaults.object(forKey: Key.checkForUpdates) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        hapticStrength = defaults.string(forKey: Key.hapticStrength).flatMap(HapticStrength.init) ?? .medium
        Haptics.configure(enabled: hapticsEnabled, strength: hapticStrength)
    }

    /// The on-device suggester when available and switched on.
    public var suggester: (any SnippetSuggester)? {
        suggestionsEnabled ? SnippetSuggesters.onDevice() : nil
    }

    /// The preferences shared through iCloud.
    public var synced: SyncedSettings {
        SyncedSettings(appearance: appearance, accent: accent, codeThemeID: codeThemeID,
                       codeFontSize: codeFontSize, showLineNumbers: showLineNumbers, iconStyle: iconStyle,
                       searchInCode: searchInCode, languageIconStyle: languageIconStyle, wrapLines: wrapLines,
                       smartGroups: smartGroups)
    }

    public func apply(_ remote: SyncedSettings) {
        if appearance != remote.appearance { appearance = remote.appearance }
        if accent != remote.accent { accent = remote.accent }
        if codeThemeID != remote.codeThemeID, CodeTheme.named(remote.codeThemeID) != nil { codeThemeID = remote.codeThemeID }
        if codeFontSize != remote.codeFontSize { codeFontSize = remote.codeFontSize }
        if showLineNumbers != remote.showLineNumbers { showLineNumbers = remote.showLineNumbers }
        if let style = remote.iconStyle, iconStyle != style { iconStyle = style }
        if let code = remote.searchInCode, searchInCode != code { searchInCode = code }
        if let style = remote.languageIconStyle, languageIconStyle != style { languageIconStyle = style }
        if let wrap = remote.wrapLines, wrapLines != wrap { wrapLines = wrap }
        if let groups = remote.smartGroups, smartGroups != groups { smartGroups = groups }
    }
}

extension View {
    /// Applies the user's appearance and accent colour.
    public func appSettingsStyle(_ settings: AppSettings) -> some View {
        environment(settings)
            .environment(\.iconStyle, settings.iconStyle)
            .preferredColorScheme(settings.appearance.colorScheme)
            .tint(settings.accent.color)
            #if os(iOS)
            .background(WindowTint(color: settings.accent.color))
            #endif
    }
}

public struct SyncedSettings: Codable, Equatable, Sendable {
    public var appearance: AppAppearance
    public var accent: AccentChoice
    public var codeThemeID: String
    public var codeFontSize: Double
    public var showLineNumbers: Bool
    /// Optional: absent in settings synced by earlier versions.
    public var iconStyle: IconStyle?
    public var searchInCode: Bool?
    public var languageIconStyle: LanguageIconStyle?
    public var wrapLines: Bool?
    public var smartGroups: [SmartGroup]?

    public init(appearance: AppAppearance, accent: AccentChoice, codeThemeID: String, codeFontSize: Double,
                showLineNumbers: Bool, iconStyle: IconStyle? = nil, searchInCode: Bool? = nil,
                languageIconStyle: LanguageIconStyle? = nil, wrapLines: Bool? = nil,
                smartGroups: [SmartGroup]? = nil) {
        self.appearance = appearance
        self.accent = accent
        self.codeThemeID = codeThemeID
        self.codeFontSize = codeFontSize
        self.showLineNumbers = showLineNumbers
        self.iconStyle = iconStyle
        self.searchInCode = searchInCode
        self.languageIconStyle = languageIconStyle
        self.wrapLines = wrapLines
        self.smartGroups = smartGroups
    }
}

#if os(iOS)
/// SwiftUI's `.tint` doesn't reach system bar buttons such as the iPad sidebar toggle; they take
/// the window's tint. This keeps the window's tint on the accent colour.
private struct WindowTint: UIViewRepresentable {
    let color: Color

    func makeUIView(context: Context) -> TintingView { TintingView() }

    func updateUIView(_ view: TintingView, context: Context) {
        view.tint = UIColor(color)
    }

    final class TintingView: UIView {
        var tint: UIColor? { didSet { apply() } }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            guard let tint, let window, window.tintColor != tint else { return }
            window.tintColor = tint
        }
    }
}
#endif
