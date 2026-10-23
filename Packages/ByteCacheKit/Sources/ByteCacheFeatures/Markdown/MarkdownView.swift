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
        case .code(let language, let text) where language?.lowercased() == "mermaid":
            MermaidView(source: text)
        case .code(let language, let text):
            CodeView(code: text, language: language.flatMap(LanguageName.catalogID) ?? "plaintext")
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .rule:
            Divider()
        case .table(let header, let alignments, let rows):
            MarkdownTableView(header: header, alignments: alignments, rows: rows)
        }
    }

    @ViewBuilder
    private func markerView(_ marker: MarkdownBlock.ListMarker) -> some View {
        switch marker {
        case .bullet: Text("•").foregroundStyle(.secondary)
        case .number(let n): Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
        case .task(let done):
            Icon(done ? .checkboxChecked : .checkbox).foregroundStyle(done ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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

/// A GitHub-style table (CP-73): bold header, lines between rows, sideways scrolling when it's wide.
struct MarkdownTableView: View {
    let header: [String]
    let alignments: [MarkdownBlock.TableAlignment]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        cell(header[column], column: column).fontWeight(.semibold)
                    }
                }
                .background(.secondary.opacity(0.12))
                ForEach(rows.indices, id: \.self) { row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            cell(rows[row][column], column: column)
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func cell(_ text: String, column: Int) -> some View {
        let alignment = column < alignments.count ? alignments[column] : .leading
        return Text(MarkdownDocument.inline(text))
            .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
            .frame(minWidth: 60, maxWidth: 320, alignment: alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .gridColumnAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
    }
}
