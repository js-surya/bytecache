import SwiftUI

/// The coloured rounded-square glyph used by iOS Settings rows.
public struct SettingsIcon: View {
    let systemName: String
    let color: Color

    public init(_ systemName: String, color: Color) {
        self.systemName = systemName
        self.color = color
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Icon, title and an optional trailing value — one Settings row.
struct SettingsLabel: View {
    let title: String
    let systemName: String
    let color: Color
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName, color: color)
            Text(title)
            Spacer(minLength: 8)
            if let value {
                Text(value).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Mini code sample drawn with a theme's colours (no highlighter needed).
struct ThemeSwatch: View {
    let palette: CodeTheme.Palette

    var body: some View {
        let bg = CodeTheme.color(palette.background), fg = CodeTheme.color(palette.foreground)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) { bar(CodeTheme.color(palette.keyword), 10); bar(fg, 14) }
            HStack(spacing: 3) { bar(fg, 6); bar(CodeTheme.color(palette.string), 16) }
            HStack(spacing: 3) { bar(CodeTheme.color(palette.keyword), 8); bar(fg, 10) }
        }
        .padding(6)
        .frame(width: 52, height: 36, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
        .accessibilityHidden(true)
    }

    private func bar(_ color: Color, _ width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: width, height: 4)
    }
}
