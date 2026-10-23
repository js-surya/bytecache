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
    /// Language logos in their brand colours or tinted like the other icons.
    public var languageIconStyle: LanguageIconStyle {
        didSet { defaults.set(languageIconStyle.rawValue, forKey: Key.languageIconStyle) }
    }
    /// Search matches code as well as titles and descriptions.
    public var searchInCode: Bool { didSet { defaults.set(searchInCode, forKey: Key.searchInCode) } }
    public var showLineNumbers: Bool { didSet { defaults.set(showLineNumbers, forKey: Key.lineNumbers) } }
    /// Long lines wrap in the code view instead of scrolling sideways.
    public var wrapLines: Bool { didSet { defaults.set(wrapLines, forKey: Key.wrapLines) } }
    /// Mac, device-only: Quick Search in the menu bar, and its global keyboard shortcut.
    public var quickSearchInMenuBar: Bool { didSet { defaults.set(quickSearchInMenuBar, forKey: Key.quickSearchMenuBar) } }
    public var quickSearchShortcut: QuickSearchShortcut {
        didSet { defaults.set(quickSearchShortcut.rawValue, forKey: Key.quickSearchShortcut) }
    }
    /// Mac, device-only: what Return and ⌥Return do in Quick Search and the menu bar (⌘Return opens).
    public var quickSearchReturnAction: QuickSearchAction {
        didSet { defaults.set(quickSearchReturnAction.rawValue, forKey: Key.quickSearchReturn) }
    }
    public var quickSearchOptionReturnAction: QuickSearchAction {
        didSet { defaults.set(quickSearchOptionReturnAction.rawValue, forKey: Key.quickSearchOptionReturn) }
    }
    /// Mac, device-only (CP-69): what the menu bar and Quick Search list before anything is typed.
    public var quickSearchStart: QuickSearchStart {
        didSet { defaults.set(quickSearchStart.rawValue, forKey: Key.quickSearchStart) }
    }
    public var quickSearchClearsOnOpen: Bool {
        didSet { defaults.set(quickSearchClearsOnOpen, forKey: Key.quickSearchClears) }
    }
    public var menuBarPanelSize: MenuBarPanelSize {
        didSet { defaults.set(menuBarPanelSize.rawValue, forKey: Key.menuBarPanelSize) }
    }
    /// No Dock icon or menu bar: ByteCache lives in the menu bar icon, which therefore stays on.
    public var menuBarOnly: Bool {
        didSet {
            defaults.set(menuBarOnly, forKey: Key.menuBarOnly)
            if menuBarOnly && !quickSearchInMenuBar { quickSearchInMenuBar = true }
        }
    }
    /// When snippets expire (ByteStash doesn't store this), per server and snippet.
    public var snippetExpiries: SnippetExpiries {
        didSet { defaults.set(try? JSONEncoder().encode(snippetExpiries), forKey: Key.snippetExpiries) }
    }
    /// Saved rule-based groups, shown in the sidebar.
    public var smartGroups: [SmartGroup] {
        didSet { defaults.set(try? JSONEncoder().encode(smartGroups), forKey: Key.smartGroups) }
    }
    /// Device-only switches (never synced themselves).
    public var iCloudSyncEnabled: Bool { didSet { defaults.set(iCloudSyncEnabled, forKey: Key.iCloudSync) } }
    public var handoffEnabled: Bool { didSet { defaults.set(handoffEnabled, forKey: Key.handoff) } }
    public var suggestionsEnabled: Bool { didSet { defaults.set(suggestionsEnabled, forKey: Key.suggestions) } }
    /// Device-only: how many AI Notes to keep (the oldest go first).
    public var aiNotesLimit: Int { didSet { defaults.set(aiNotesLimit, forKey: Key.aiNotesLimit) } }
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
        static let appearance = "appearance", accent = "accent", codeThemeID = "codeThemeID", searchInCode = "searchInCode"
        static let languageIconStyle = "languageIconStyle"
        static let fontSize = "codeFontSize", lineNumbers = "showLineNumbers", wrapLines = "wrapLines", smartGroups = "smartGroups"
        static let quickSearchMenuBar = "quickSearchInMenuBar", quickSearchShortcut = "quickSearchShortcut"
        static let quickSearchReturn = "quickSearchReturnAction", quickSearchOptionReturn = "quickSearchOptionReturnAction"
        static let quickSearchStart = "quickSearchStart", quickSearchClears = "quickSearchClearsOnOpen"
        static let menuBarPanelSize = "menuBarPanelSize", menuBarOnly = "menuBarOnly"
        static let snippetExpiries = "snippetExpiries"
        static let aiNotesLimit = "aiNotesLimit"
        static let iCloudSync = "iCloudSyncEnabled", handoff = "handoffEnabled", suggestions = "suggestionsEnabled"
        static let haptics = "hapticsEnabled", hapticStrength = "hapticStrength"
    }

    public init(defaults: UserDefaults = AppEnvironment.sharedDefaults) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init) ?? .system
        accent = defaults.string(forKey: Key.accent).flatMap(AccentChoice.init) ?? .blue
        languageIconStyle = defaults.string(forKey: Key.languageIconStyle).flatMap(LanguageIconStyle.init) ?? .color
        searchInCode = defaults.bool(forKey: Key.searchInCode)
        let storedTheme = defaults.string(forKey: Key.codeThemeID) ?? CodeTheme.defaultID
        codeThemeID = CodeTheme.named(storedTheme) == nil ? CodeTheme.defaultID : storedTheme
        let size = defaults.object(forKey: Key.fontSize) as? Double ?? 14
        codeFontSize = min(max(size, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        showLineNumbers = defaults.object(forKey: Key.lineNumbers) as? Bool ?? true
        wrapLines = defaults.bool(forKey: Key.wrapLines)
        quickSearchInMenuBar = defaults.object(forKey: Key.quickSearchMenuBar) as? Bool ?? true
        quickSearchShortcut = defaults.string(forKey: Key.quickSearchShortcut).flatMap(QuickSearchShortcut.init) ?? .controlOptionSpace
        quickSearchReturnAction = defaults.string(forKey: Key.quickSearchReturn).flatMap(QuickSearchAction.init) ?? .copy
        quickSearchOptionReturnAction = defaults.string(forKey: Key.quickSearchOptionReturn).flatMap(QuickSearchAction.init) ?? .paste
        quickSearchStart = defaults.string(forKey: Key.quickSearchStart).flatMap(QuickSearchStart.init) ?? .recent
        quickSearchClearsOnOpen = defaults.object(forKey: Key.quickSearchClears) as? Bool ?? true
        menuBarPanelSize = defaults.string(forKey: Key.menuBarPanelSize).flatMap(MenuBarPanelSize.init) ?? .medium
        menuBarOnly = defaults.bool(forKey: Key.menuBarOnly)
        snippetExpiries = defaults.data(forKey: Key.snippetExpiries)
            .flatMap { try? JSONDecoder().decode(SnippetExpiries.self, from: $0) } ?? SnippetExpiries()
        smartGroups = defaults.data(forKey: Key.smartGroups).flatMap { try? JSONDecoder().decode([SmartGroup].self, from: $0) } ?? []
        iCloudSyncEnabled = defaults.object(forKey: Key.iCloudSync) as? Bool ?? true
        handoffEnabled = defaults.object(forKey: Key.handoff) as? Bool ?? true
        suggestionsEnabled = defaults.object(forKey: Key.suggestions) as? Bool ?? true
        aiNotesLimit = (defaults.object(forKey: Key.aiNotesLimit) as? Int).flatMap { AINoteStore.limits.contains($0) ? $0 : nil } ?? 50
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
                       codeFontSize: codeFontSize, showLineNumbers: showLineNumbers,
                       searchInCode: searchInCode, languageIconStyle: languageIconStyle, wrapLines: wrapLines,
                       smartGroups: smartGroups, snippetExpiries: snippetExpiries)
    }

    public func apply(_ remote: SyncedSettings) {
        if appearance != remote.appearance { appearance = remote.appearance }
        if accent != remote.accent { accent = remote.accent }
        if codeThemeID != remote.codeThemeID, CodeTheme.named(remote.codeThemeID) != nil { codeThemeID = remote.codeThemeID }
        if codeFontSize != remote.codeFontSize { codeFontSize = remote.codeFontSize }
        if showLineNumbers != remote.showLineNumbers { showLineNumbers = remote.showLineNumbers }
        if let code = remote.searchInCode, searchInCode != code { searchInCode = code }
        if let style = remote.languageIconStyle, languageIconStyle != style { languageIconStyle = style }
        if let wrap = remote.wrapLines, wrapLines != wrap { wrapLines = wrap }
        if let groups = remote.smartGroups, smartGroups != groups { smartGroups = groups }
        if let expiries = remote.snippetExpiries, snippetExpiries != expiries { snippetExpiries = expiries }
    }
}

extension View {
    /// Applies the user's appearance and accent colour.
    public func appSettingsStyle(_ settings: AppSettings) -> some View {
        environment(settings)
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
    /// Optional: absent in settings synced by earlier versions. (Versions before 1.3 also synced an
    /// icon style; it's ignored.)
    public var searchInCode: Bool?
    public var languageIconStyle: LanguageIconStyle?
    public var wrapLines: Bool?
    public var smartGroups: [SmartGroup]?
    public var snippetExpiries: SnippetExpiries?

    public init(appearance: AppAppearance, accent: AccentChoice, codeThemeID: String, codeFontSize: Double,
                showLineNumbers: Bool, searchInCode: Bool? = nil,
                languageIconStyle: LanguageIconStyle? = nil, wrapLines: Bool? = nil,
                smartGroups: [SmartGroup]? = nil, snippetExpiries: SnippetExpiries? = nil) {
        self.appearance = appearance
        self.accent = accent
        self.codeThemeID = codeThemeID
        self.codeFontSize = codeFontSize
        self.showLineNumbers = showLineNumbers
        self.searchInCode = searchInCode
        self.languageIconStyle = languageIconStyle
        self.wrapLines = wrapLines
        self.smartGroups = smartGroups
        self.snippetExpiries = snippetExpiries
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
