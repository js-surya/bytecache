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
    /// Search matches code as well as titles and descriptions.
    public var searchInCode: Bool { didSet { defaults.set(searchInCode, forKey: Key.searchInCode) } }
    public var showLineNumbers: Bool { didSet { defaults.set(showLineNumbers, forKey: Key.lineNumbers) } }
    /// Device-only switches (never synced themselves).
    public var iCloudSyncEnabled: Bool { didSet { defaults.set(iCloudSyncEnabled, forKey: Key.iCloudSync) } }
    public var handoffEnabled: Bool { didSet { defaults.set(handoffEnabled, forKey: Key.handoff) } }
    public var suggestionsEnabled: Bool { didSet { defaults.set(suggestionsEnabled, forKey: Key.suggestions) } }
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
        static let fontSize = "codeFontSize", lineNumbers = "showLineNumbers"
        static let iCloudSync = "iCloudSyncEnabled", handoff = "handoffEnabled", suggestions = "suggestionsEnabled"
        static let haptics = "hapticsEnabled", hapticStrength = "hapticStrength"
    }

    public init(defaults: UserDefaults = AppEnvironment.sharedDefaults) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init) ?? .system
        accent = defaults.string(forKey: Key.accent).flatMap(AccentChoice.init) ?? .blue
        iconStyle = defaults.string(forKey: Key.iconStyle).flatMap(IconStyle.init) ?? .sfSymbols
        searchInCode = defaults.bool(forKey: Key.searchInCode)
        let storedTheme = defaults.string(forKey: Key.codeThemeID) ?? CodeTheme.defaultID
        codeThemeID = CodeTheme.named(storedTheme) == nil ? CodeTheme.defaultID : storedTheme
        let size = defaults.object(forKey: Key.fontSize) as? Double ?? 14
        codeFontSize = min(max(size, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        showLineNumbers = defaults.object(forKey: Key.lineNumbers) as? Bool ?? true
        iCloudSyncEnabled = defaults.object(forKey: Key.iCloudSync) as? Bool ?? true
        handoffEnabled = defaults.object(forKey: Key.handoff) as? Bool ?? true
        suggestionsEnabled = defaults.object(forKey: Key.suggestions) as? Bool ?? true
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
                       searchInCode: searchInCode)
    }

    public func apply(_ remote: SyncedSettings) {
        if appearance != remote.appearance { appearance = remote.appearance }
        if accent != remote.accent { accent = remote.accent }
        if codeThemeID != remote.codeThemeID, CodeTheme.named(remote.codeThemeID) != nil { codeThemeID = remote.codeThemeID }
        if codeFontSize != remote.codeFontSize { codeFontSize = remote.codeFontSize }
        if showLineNumbers != remote.showLineNumbers { showLineNumbers = remote.showLineNumbers }
        if let style = remote.iconStyle, iconStyle != style { iconStyle = style }
        if let code = remote.searchInCode, searchInCode != code { searchInCode = code }
    }
}

extension View {
    /// Applies the user's appearance and accent colour.
    public func appSettingsStyle(_ settings: AppSettings) -> some View {
        environment(settings)
            .environment(\.iconStyle, settings.iconStyle)
            .preferredColorScheme(settings.appearance.colorScheme)
            .tint(settings.accent.color)
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

    public init(appearance: AppAppearance, accent: AccentChoice, codeThemeID: String, codeFontSize: Double,
                showLineNumbers: Bool, iconStyle: IconStyle? = nil, searchInCode: Bool? = nil) {
        self.appearance = appearance
        self.accent = accent
        self.codeThemeID = codeThemeID
        self.codeFontSize = codeFontSize
        self.showLineNumbers = showLineNumbers
        self.iconStyle = iconStyle
        self.searchInCode = searchInCode
    }
}
