import SwiftUI
import ByteCatchCore
import ByteCatchFeatures

/// Sidebar | list | detail. Collapses to a stack on iPhone.
struct MainSplitView: View {
    let services: AppServices
    @State private var sidebar: SidebarModel
    @State private var list: SnippetListModel
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var selectedSnippet: Snippet.ID?
    @State private var editor: SnippetEditorModel?

    init(services: AppServices) {
        self.services = services
        _sidebar = State(initialValue: SidebarModel(session: services.session))
        _list = State(initialValue: SnippetListModel(session: services.session, cache: services.cache))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: sidebar, selection: $sidebarSelection, session: services.session)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
                #endif
        } content: {
            SnippetListView(model: list, selection: $selectedSnippet)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { startEditing(nil) } label: { Label("New Snippet", systemImage: "square.and.pencil") }
                            .keyboardShortcut("n", modifiers: .command)
                    }
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
                #endif
        } detail: {
            if let id = selectedSnippet, let snippet = list.snippets.first(where: { $0.id == id }) {
                SnippetDetailView(snippet: snippet, list: list) { startEditing(snippet) }
            } else {
                ContentUnavailableView("No Snippet Selected", systemImage: "curlybraces",
                                       description: Text("Pick a snippet, or press ⌘N to create one."))
            }
        }
        .task(id: sidebarSelection) {
            list.selection = sidebarSelection ?? .all
            selectedSnippet = nil
            await list.refresh()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-BCSelectFirst") { selectedSnippet = list.snippets.first?.id }
            #endif
        }
        .sheet(item: $editor) { model in
            NavigationStack {
                EditorView(model: model, knownCategories: sidebar.categories) { saved in
                    list.didSave(saved)
                    selectedSnippet = saved.id
                    editor = nil
                    Task { await sidebar.load() }
                } onCancel: {
                    editor = nil
                }
            }
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 600)
            #endif
        }
    }

    private func startEditing(_ snippet: Snippet?) {
        editor = SnippetEditorModel(existing: snippet, session: services.session, detector: services.detector)
    }
}
