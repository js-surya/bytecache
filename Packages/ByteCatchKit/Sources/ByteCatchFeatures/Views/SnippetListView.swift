import ByteCatchCore
import SwiftUI

public struct SnippetListView: View {
    @Bindable var model: SnippetListModel
    @Binding var selection: Snippet.ID?
    let showsSearchField: Bool

    /// `showsSearchField: false` when a Search tab owns searching (iPhone tab layout).
    public init(model: SnippetListModel, selection: Binding<Snippet.ID?>, showsSearchField: Bool = true) {
        self.model = model
        _selection = selection
        self.showsSearchField = showsSearchField
    }

    public var body: some View {
        List(selection: $selection) {
            if model.pinnedSection.isEmpty {
                ForEach(model.snippets) { row($0) }
            } else {
                Section {
                    ForEach(model.pinnedSection) { row($0) }
                } header: {
                    Label("Pinned", symbol: .pinFill).foregroundStyle(.orange)
                }
                Section("Snippets") {
                    ForEach(model.otherSection) { row($0) }
                }
            }
        }
        .overlay {
            if model.snippets.isEmpty && !model.isLoading {
                if model.searchText.isEmpty {
                    ContentUnavailableView("No Snippets", symbol: .tray, description: Text("Nothing here yet."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if model.isOffline {
                Label("Offline — showing saved snippets", symbol: .offline)
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(.yellow.opacity(0.25))
            }
        }
        .modifier(OptionalSearch(enabled: showsSearchField, model: model))
        .onChange(of: model.searchText) { model.searchTextChanged() }
        .refreshable { await model.refresh() }
        .navigationTitle(model.selection.title)
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Sort", selection: $model.sort) {
                        Text("Newest").tag(SnippetSort.newest)
                        Text("Oldest").tag(SnippetSort.oldest)
                        Text("A–Z").tag(SnippetSort.alphaAsc)
                        Text("Z–A").tag(SnippetSort.alphaDesc)
                    }
                    Toggle("Search Code Too", isOn: $model.searchCode)
                } label: {
                    Label("Sort and Search Options", symbol: .sort)
                }
            }
        }
        .onChange(of: model.sort) { Task { await model.refresh() } }
        .onChange(of: model.searchCode) { if !model.searchText.isEmpty { Task { await model.refresh() } } }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }

    private func row(_ snippet: Snippet) -> some View {
        SnippetRow(snippet: snippet)
            .tag(snippet.id)
            .task { await model.loadMoreIfNeeded(current: snippet) }
            .contextMenu { SnippetActions(snippet: snippet, model: model) }
            #if os(iOS)
            .swipeActions(edge: .leading) {
                Button { Task { await model.togglePin(snippet) } } label: {
                    Label(snippet.isPinned ? "Unpin" : "Pin", symbol: snippet.isPinned ? .pinOff : .pin)
                }.tint(.orange)
                Button { Task { await model.toggleFavorite(snippet) } } label: {
                    Label(snippet.isFavorite ? "Unfavorite" : "Favorite", symbol: snippet.isFavorite ? .starOff : .star)
                }.tint(.yellow)
            }
            .swipeActions(edge: .trailing) {
                if model.selection == .recycleBin {
                    Button(role: .destructive) { Task { await model.deletePermanently(snippet) } } label: {
                        Label("Delete Forever", symbol: .trashForever)
                    }
                    Button { Task { await model.restore(snippet) } } label: {
                        Label("Restore", symbol: .restore)
                    }.tint(.green)
                } else {
                    Button(role: .destructive) { Task { await model.recycle(snippet) } } label: {
                        Label("Recycle", symbol: .trash)
                    }
                }
            }
            #endif
    }
}

/// Context-menu actions shared by rows and the detail view.
public struct SnippetActions: View {
    let snippet: Snippet
    let model: SnippetListModel

    public init(snippet: Snippet, model: SnippetListModel) {
        self.snippet = snippet
        self.model = model
    }

    private var allCode: String {
        snippet.fragments.sorted { $0.position < $1.position }.map(\.code).joined(separator: "\n\n")
    }

    public var body: some View {
        if model.selection == .recycleBin {
            Button { Task { await model.restore(snippet) } } label: { Label("Restore", symbol: .restore) }
            Button(role: .destructive) { Task { await model.deletePermanently(snippet) } } label: {
                Label("Delete Forever", symbol: .trashForever)
            }
        } else {
            Button { Pasteboard.copy(allCode) } label: { Label("Copy Code", symbol: .copy) }
            ShareLink(item: allCode) { Label("Share", symbol: .share) }
            Divider()
            Button { Task { await model.togglePin(snippet) } } label: {
                Label(snippet.isPinned ? "Unpin" : "Pin", symbol: snippet.isPinned ? .pinOff : .pin)
            }
            Button { Task { await model.toggleFavorite(snippet) } } label: {
                Label(snippet.isFavorite ? "Unfavorite" : "Favorite", symbol: snippet.isFavorite ? .starOff : .star)
            }
            Divider()
            Button(role: .destructive) { Task { await model.recycle(snippet) } } label: {
                Label("Move to Recycle Bin", symbol: .trash)
            }
        }
    }
}

/// `searchFocused` needs iOS 18 / macOS 15; on older systems ⌘F is a no-op.
private struct SearchFocus: ViewModifier {
    let request: Int
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            content
                .searchFocused($focused)
                .onChange(of: request) { focused = true }
        } else {
            content
        }
    }
}

private struct OptionalSearch: ViewModifier {
    let enabled: Bool
    @Bindable var model: SnippetListModel

    func body(content: Content) -> some View {
        if enabled {
            content
                .searchable(text: $model.searchText, prompt: "Search snippets")
                .modifier(SearchFocus(request: model.searchFocusRequest))
        } else {
            content
        }
    }
}
