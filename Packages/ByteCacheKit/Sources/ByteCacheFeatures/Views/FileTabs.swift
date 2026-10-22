import ByteCacheCore
import Foundation
import SwiftUI

/// Line count and size of one file, for the snippet status bar (CP-70).
struct FileStats: Equatable {
    let lines: Int
    let bytes: Int

    init(_ code: String) {
        let breaks = code.reduce(0) { $1.isNewline ? $0 + 1 : $0 }
        let endsWithBreak = code.last?.isNewline ?? false
        lines = code.isEmpty ? 0 : breaks + (endsWithBreak ? 0 : 1)
        bytes = code.utf8.count
    }

    var linesText: String { lines == 1 ? "1 line" : "\(lines) lines" }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}

/// One tab per file of a snippet (Mac and iPad); iPhone shows the files as stacked cards instead.
struct FileTabStrip: View {
    let fragments: [Fragment]
    @Binding var selection: Int?

    private var selectedID: Int? { selection ?? fragments.first?.id }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(fragments) { fragment in
                    let selected = fragment.id == selectedID
                    Button { selection = fragment.id } label: {
                        HStack(spacing: 6) {
                            LanguageIconView(fragment.language, size: 13)
                            Text(Self.name(of: fragment)).lineLimit(1)
                        }
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        // ⌘⇧] / ⌘⇧[ move between files, like tabs elsewhere on the Mac.
        .background {
            Button("") { step(1) }.keyboardShortcut("]", modifiers: [.command, .shift]).hidden()
            Button("") { step(-1) }.keyboardShortcut("[", modifiers: [.command, .shift]).hidden()
        }
    }

    private func step(_ offset: Int) {
        guard let index = fragments.firstIndex(where: { $0.id == selectedID }) else { return }
        let next = (index + offset + fragments.count) % fragments.count
        selection = fragments[next].id
    }

    static func name(of fragment: Fragment) -> String {
        fragment.fileName.isEmpty ? LanguageName.display(fragment.language) : fragment.fileName
    }
}

/// Bottom bar under a snippet (Mac and iPad): the shown file's language, lines and size, and Copy.
struct SnippetStatusBar: View {
    let fragment: Fragment
    let onCopy: () -> Void
    @State private var copied = false

    var body: some View {
        let stats = FileStats(fragment.code)
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                LanguageIconView(fragment.language, size: 12)
                Text(LanguageName.display(fragment.language))
            }
            Text(stats.linesText)
            Text(stats.sizeText)
            Spacer(minLength: 8)
            Button {
                Pasteboard.copy(fragment.code, toast: false)
                onCopy()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", symbol: copied ? .check : .copy)
            }
            .buttonStyle(.borderless)
            .help("Copy \(FileTabStrip.name(of: fragment))")
        }
        .lineLimit(1)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
