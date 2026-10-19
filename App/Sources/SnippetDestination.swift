import SwiftUI
import ByteCacheCore
import ByteCacheFeatures

/// Shows a snippet by id: the list's copy when it has one (so pin/favourite changes show live),
/// otherwise the offline cache or a fetch — opening must not depend on which page the list loaded.
struct SnippetDestination: View {
    let id: Snippet.ID
    let list: SnippetListModel
    let services: AppServices
    let onEdit: (Snippet) -> Void
    @State private var loaded: Snippet?
    @State private var failed: String?

    var body: some View {
        if let snippet = list.snippets.first(where: { $0.id == id }) ?? loaded {
            SnippetDetailView(snippet: snippet, list: list) { onEdit(snippet) }
        } else if let failed {
            ContentUnavailableView("Couldn't Open Snippet", symbol: .warning, description: Text(failed))
        } else {
            ProgressView()
                .task(id: id) { await load() }
        }
    }

    private func load() async {
        guard let client = services.session.client else { return }
        if let cached = services.cache?.snippet(id: id, server: client.server) { loaded = cached }
        do {
            loaded = try await client.snippet(id: id)
        } catch {
            if loaded == nil { failed = ErrorText.message(for: error) }
        }
    }
}
