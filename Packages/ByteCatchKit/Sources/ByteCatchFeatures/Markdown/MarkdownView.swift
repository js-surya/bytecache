import SwiftUI

/// Renders a Markdown snippet as formatted text.
public struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    public init(_ text: String) {
        blocks = MarkdownDocument.parse(text)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownDocument.inline(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(MarkdownDocument.inline(text))
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                markerView(marker)
                Text(MarkdownDocument.inline(text))
                    .strikethrough(marker == .task(done: true), color: .secondary)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .quote(let text):
            Text(MarkdownDocument.inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(.tint.opacity(0.6)).frame(width: 3) }
        case .code(let language, let text):
            CodeView(code: text, language: language.flatMap(LanguageName.catalogID) ?? "plaintext")
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .rule:
            Divider()
        }
    }

    @ViewBuilder
    private func markerView(_ marker: MarkdownBlock.ListMarker) -> some View {
        switch marker {
        case .bullet: Text("•").foregroundStyle(.secondary)
        case .number(let n): Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
        case .task(let done):
            Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(done ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.weight(.semibold)
        default: .headline
        }
    }
}
