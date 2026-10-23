import SwiftUI

/// The kept Explain result under a snippet's code (CP-79): who wrote it and when, whether the code has
/// changed since, and Copy / Explain Again / Delete. Read-only, so it stays clearly AI-written.
struct AINoteCard: View {
    let note: AINote
    let code: String
    /// This device can make a new one (Apple Intelligence available here).
    let canExplainAgain: Bool
    let onExplainAgain: () -> Void
    let onDelete: () -> Void
    @State private var expanded = false

    private var long: Bool { note.text.count > 360 || note.text.filter { $0 == "\n" }.count > 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("AI Note", symbol: .sparkles)
                    .font(.headline)
                    .foregroundStyle(.tint)
                Spacer()
                Menu {
                    Button { Pasteboard.copy(note.text) } label: { Label("Copy", symbol: .copy) }
                    if canExplainAgain {
                        Button(action: onExplainAgain) { Label("Explain Again", symbol: .sparkles) }
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) { Label("Delete Note", symbol: .trash) }
                } label: {
                    Label("More", symbol: .more).labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            Text("Explained by Apple Intelligence \(note.created.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if note.isStale(for: code) {
                HStack(spacing: 8) {
                    Label("The code changed since this was written.", symbol: .warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if canExplainAgain {
                        Button("Explain Again", action: onExplainAgain)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderless)
                    }
                }
            }
            MarkdownView(note.text)
                .padding(-14) // MarkdownView pads itself; the card already does.
                .padding(.top, 4)
                .frame(maxHeight: long && !expanded ? 150 : nil, alignment: .top)
                .clipped()
            if long {
                Button(expanded ? "Show Less" : "Show More") { withAnimation { expanded.toggle() } }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.tint.opacity(0.18)))
    }
}
