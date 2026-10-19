import Foundation
import HighlightSwift
#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

/// One coloured stretch of code, in UTF-16 offsets of the editor's text.
public struct ColorRun: Equatable, Sendable {
    public let range: NSRange
    public let hex: String
}

/// Colours for the live editor, from the same highlight.js grammars and themes as the viewer.
@MainActor
public final class EditorHighlighter {
    /// Bigger texts stay plain: highlighting runs on every pause in typing.
    public static let maxLength = 40_000
    private let highlight = Highlight()

    public init() {}

    /// Nil when the text is too long or highlighting failed; empty for plain text.
    public func runs(for code: String, language: String, palette: CodeTheme.Palette) async -> [ColorRun]? {
        let ns = code as NSString
        guard ns.length <= Self.maxLength else { return nil }
        let mode = HighlightAlias.mode(for: language)
        switch mode {
        case .language(.plaintext), .languageIgnoreIllegal(.plaintext): return []
        default: break
        }
        guard let result = try? await highlight.request(code, mode: mode, colors: palette.colors) else { return nil }
        let colored = NSAttributedString(result.attributedText)
        // highlight.js gets the code without surrounding whitespace.
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard colored.string == trimmed else { return nil }
        let leading = trimmed.isEmpty ? 0 : ns.range(of: trimmed).location
        var runs: [ColorRun] = []
        colored.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: colored.length)) { value, range, _ in
            guard let color = value as? PlatformColor, let hex = Self.hex(color) else { return }
            runs.append(ColorRun(range: NSRange(location: range.location + leading, length: range.length), hex: hex))
        }
        return runs
    }

    private static func hex(_ color: PlatformColor) -> String? {
        guard let srgb = color.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = srgb.components, c.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}
