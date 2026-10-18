import ByteCatchCore
import Observation
import SwiftUI

public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
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

public enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
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
    public var showLineNumbers: Bool { didSet { defaults.set(showLineNumbers, forKey: Key.lineNumbers) } }
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
        static let appearance = "appearance", accent = "accent", codeThemeID = "codeThemeID"
        static let fontSize = "codeFontSize", lineNumbers = "showLineNumbers"
    }

    public init(defaults: UserDefaults = AppEnvironment.sharedDefaults) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init) ?? .system
        accent = defaults.string(forKey: Key.accent).flatMap(AccentChoice.init) ?? .blue
        let storedTheme = defaults.string(forKey: Key.codeThemeID) ?? CodeTheme.defaultID
        codeThemeID = CodeTheme.named(storedTheme) == nil ? CodeTheme.defaultID : storedTheme
        let size = defaults.object(forKey: Key.fontSize) as? Double ?? 14
        codeFontSize = min(max(size, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        showLineNumbers = defaults.object(forKey: Key.lineNumbers) as? Bool ?? true
    }
}

extension View {
    /// Applies the user's appearance and accent colour.
    public func appSettingsStyle(_ settings: AppSettings) -> some View {
        environment(settings)
            .preferredColorScheme(settings.appearance.colorScheme)
            .tint(settings.accent.color)
    }
}
