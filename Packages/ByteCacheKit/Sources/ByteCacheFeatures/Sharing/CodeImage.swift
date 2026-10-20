import ByteCacheCore
import HighlightSwift
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// What goes behind the code window in a shared image.
public enum CodeCardBackground: String, CaseIterable, Identifiable, Sendable {
    case accent, theme, none

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .accent: "Accent"
        case .theme: "Theme"
        case .none: "None"
        }
    }
}

/// Code shown as a picture: a window with the file name, the highlighted code in the code theme,
/// and a background. Takes already-highlighted lines, because the image is drawn in one pass.
struct CodeCardView: View {
    let fileName: String
    let lines: [AttributedString]
    let truncated: Bool
    let palette: CodeTheme.Palette
    let fontSize: Double
    let showLineNumbers: Bool
    let background: CodeCardBackground
    let accent: Color

    static let maxWidth: CGFloat = 760

    var body: some View {
        window
            .padding(background == .none ? 0 : 36)
            .background { backdrop }
    }

    private var window: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in
                    Circle().fill(color.opacity(0.85)).frame(width: 11, height: 11)
                }
                Text(fileName.isEmpty ? "Untitled" : fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodeTheme.color(palette.foreground).opacity(0.6))
                    .padding(.leading, 8)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            code
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .padding(.top, 4)
        }
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(CodeTheme.color(palette.background), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(background == .none ? 0 : 0.35), radius: 18, y: 8)
    }

    private var code: some View {
        let shown = truncated ? lines + [AttributedString("…")] : lines
        let digits = String(repeating: "8", count: String(shown.count).count)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(shown.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    if showLineNumbers {
                        ZStack(alignment: .trailing) {
                            Text(digits).hidden()
                            Text(truncated && index == shown.count - 1 ? "" : "\(index + 1)")
                                .foregroundStyle(CodeTheme.color(palette.foreground).opacity(0.35))
                        }
                    }
                    Text(shown[index].characters.isEmpty ? AttributedString(" ") : shown[index])
                        .foregroundStyle(CodeTheme.color(palette.foreground))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
    }

    @ViewBuilder
    private var backdrop: some View {
        switch background {
        case .accent:
            LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .theme:
            CodeTheme.color(palette.background).brightness(0.08)
        case .none:
            Color.clear
        }
    }
}

/// Highlights a file and draws it as an image.
@MainActor
enum CodeImage {
    static let maxLines = 60
    private static let highlighter = Highlight()

    /// The file's lines, highlighted, at most `maxLines`; and whether more were cut.
    static func lines(of fragment: Fragment, palette: CodeTheme.Palette) async -> (lines: [AttributedString], truncated: Bool) {
        let all = CodeLines.plain(fragment.code)
        let truncated = all.count > maxLines
        let code = all.prefix(maxLines).joined(separator: "\n")
        var lines = code.split(separator: "\n", omittingEmptySubsequences: false).map { AttributedString(String($0)) }
        if let result = try? await highlighter.request(code, mode: HighlightAlias.mode(for: fragment.language), colors: palette.colors),
           let split = CodeLines.split(result.attributedText, original: code) {
            lines = split
        }
        return (lines, truncated)
    }

    static func render(_ card: CodeCardView, scale: CGFloat = 3) -> PlatformImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        renderer.isOpaque = card.background != .none
        #if canImport(UIKit)
        return renderer.uiImage
        #else
        return renderer.nsImage
        #endif
    }
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#else
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#endif

/// Share as Image: preview, options, then share or copy the picture.
struct CodeImageSheet: View {
    let fragment: Fragment
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var background = CodeCardBackground.accent
    @State private var showLineNumbers = true
    @State private var highlighted: (lines: [AttributedString], truncated: Bool)?
    @State private var image: PlatformImage?
    @State private var copied = false

    var body: some View {
        let palette = settings.codeTheme.palette(for: colorScheme)
        VStack(spacing: 16) {
            ScrollView {
                Group {
                    if let image {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 560)
                            .accessibilityLabel("Image of \(fragment.fileName.isEmpty ? "the code" : fragment.fileName)")
                    } else {
                        LoadingMark("Drawing…")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding()
            }
            SettingsList {
                Picker("Background", selection: $background) {
                    ForEach(CodeCardBackground.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Line Numbers", isOn: $showLineNumbers)
                if highlighted?.truncated == true {
                    Text("Long files are cut after \(CodeImage.maxLines) lines.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: 180)
        }
        .navigationTitle("Share as Image")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            if let image {
                ToolbarItem(placement: .primaryAction) {
                    Button { copy(image) } label: { Label(copied ? "Copied" : "Copy Image", symbol: copied ? .check : .copy) }
                }
                ToolbarItem(placement: .primaryAction) {
                    let picture = Image(platformImage: image)
                    SwiftUI.ShareLink(item: picture, preview: SharePreview(fragment.fileName.isEmpty ? "Code" : fragment.fileName, image: picture))
                }
            }
        }
        .task(id: "\(palette.hashValue)") {
            highlighted = await CodeImage.lines(of: fragment, palette: palette)
            redraw(palette)
        }
        .onChange(of: background) { redraw(palette) }
        .onChange(of: showLineNumbers) { redraw(palette) }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
        #endif
    }

    private func redraw(_ palette: CodeTheme.Palette) {
        guard let highlighted else { return }
        image = CodeImage.render(CodeCardView(
            fileName: fragment.fileName, lines: highlighted.lines, truncated: highlighted.truncated,
            palette: palette, fontSize: 14, showLineNumbers: showLineNumbers,
            background: background, accent: settings.accent.color
        ))
    }

    private func copy(_ image: PlatformImage) {
        #if canImport(UIKit)
        UIPasteboard.general.image = image
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #endif
        CopyFeedback.copied("Image Copied", toast: false)
        copied = true
    }
}
