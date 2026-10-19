import ByteCacheCore
import SwiftUI

extension Snippet {
    /// Empty or the default "Untitled snippet", so worth offering Suggest Title.
    public var needsTitle: Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || title.caseInsensitiveCompare("Untitled snippet") == .orderedSame
    }
}

/// Under an untitled snippet's title: one tap asks the on-device model for a title, then
/// Use saves it (every other field unchanged).
struct SuggestTitleBar: View {
    let snippet: Snippet
    let suggester: any SnippetSuggester
    let list: SnippetListModel

    private enum Phase: Equatable {
        case idle, suggesting, suggested(String), failed
    }

    @State private var phase = Phase.idle

    var body: some View {
        Group {
            switch phase {
            case .idle, .failed:
                Button { Task { await suggest() } } label: {
                    Label(phase == .failed ? "Couldn't Suggest — Try Again" : "Suggest Title", symbol: .sparkles)
                }
                .buttonStyle(.bordered)
            case .suggesting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Suggesting a title…").foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            case .suggested(let title):
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    HStack {
                        Button("Use Title") {
                            Task { await list.rename(snippet, to: title) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button { Task { await suggest() } } label: { Label("Try Again", symbol: .refresh) }
                            .buttonStyle(.bordered)
                        Button("Dismiss", role: .cancel) { phase = .idle }
                    }
                }
                .padding(12)
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Suggested title: \(title)")
            }
        }
        .font(.subheadline)
        .controlSize(.small)
    }

    private func suggest() async {
        phase = .suggesting
        let fragments = snippet.fragments.sorted { $0.position < $1.position }
        let code = fragments.map(\.code).joined(separator: "\n\n")
        let known = Set(list.snippets.flatMap(\.categories)).sorted()
        guard let suggestion = try? await suggester.suggest(code: code, language: fragments.first?.language ?? "plaintext",
                                                           knownCategories: known) else {
            phase = .failed
            return
        }
        let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = title.isEmpty ? .failed : .suggested(title)
    }
}
