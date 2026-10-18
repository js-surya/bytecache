import SwiftUI
import ByteCatchCore
import ByteCatchFeatures

/// A snippet in its own window (iPad and Mac).
struct SnippetWindow: View {
    let id: Int
    let services: AppServices
    @State private var snippet: Snippet?
    @State private var failed: String?
    @State private var editor: SnippetEditorModel?

    var body: some View {
        NavigationStack {
            Group {
                if let snippet {
                    SnippetDetailView(snippet: snippet, list: nil, showsOpenInWindow: false) {
                        editor = SnippetEditorModel(existing: snippet, session: services.session, detector: services.detector)
                    }
                } else if let failed {
                    ContentUnavailableView("Couldn't Open Snippet", systemImage: "exclamationmark.triangle", description: Text(failed))
                } else {
                    ProgressView()
                }
            }
        }
        .task { await load() }
        .sheet(item: $editor) { model in
            NavigationStack {
                EditorView(model: model, knownCategories: []) { saved in
                    snippet = saved
                    editor = nil
                } onCancel: { editor = nil }
            }
        }
    }

    private func load() async {
        guard let client = services.session.client else { failed = "Sign in first."; return }
        if let cached = services.cache?.snippet(id: id, server: client.server) { snippet = cached }
        do {
            snippet = try await client.snippet(id: id)
        } catch {
            if snippet == nil { failed = ErrorText.message(for: error) }
        }
    }
}
