import ByteCacheCore
import SwiftUI

public struct SnippetListView: View {
    @Environment(\.windowToolbarID) private var windowToolbarID
    @Bindable var model: SnippetListModel
    @Binding var selection: Snippet.ID?
    let showsSearchField: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(SaveQueueFlusher.self) private var saveQueue: SaveQueueFlusher?

    /// `showsSearchField: false` when a Search tab owns searching (iPhone tab layout).
    public init(model: SnippetListModel, selection: Binding<Snippet.ID?>, showsSearchField: Bool = true) {
        self.model = model
        _selection = selection
        self.showsSearchField = showsSearchField
    }

    public var body: some View {
        Group {
            if model.isSelecting {
                List(selection: $model.selectedIDs) { listContent }
                    #if os(iOS)
                    .environment(\.editMode, .constant(.active))
                    #endif
            } else {
                List(selection: $selection) { listContent }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isSelecting { BulkActionBar(model: model) }
        }
        .overlay {
            if model.snippets.isEmpty && model.isLoading {
                LoadingMark()
            } else if model.snippets.isEmpty && !model.isLoading {
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
        .navigationTitle(model.title)
        // One toolbar id for the whole window, so it can be customised (CP-71); per window, see WindowToolbarID.
        .toolbar(id: windowToolbarID) {
            if !model.isReadOnly && !model.snippets.isEmpty {
                ToolbarItem(id: "select") {
                    Button(model.isSelecting ? "Done" : "Select") { model.isSelecting.toggle() }
                }
            }
            ToolbarItem(id: "sort") {
                Menu {
                    Picker("Sort", selection: $model.sort) {
                        Text("Newest").tag(SnippetSort.newest)
                        Text("Oldest").tag(SnippetSort.oldest)
                        Text("A–Z").tag(SnippetSort.alphaAsc)
                        Text("Z–A").tag(SnippetSort.alphaDesc)
                    }
                } label: {
                    Label("Sort", symbol: .sort)
                }
            }
        }
        .onChange(of: model.sort) { Task { await model.refresh() } }
        .onChange(of: settings.searchInCode, initial: true) {
            guard model.searchCode != settings.searchInCode else { return }
            model.searchCode = settings.searchInCode
            if !model.searchText.isEmpty { Task { await model.refresh() } }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
        .logScreen("Snippet list")
    }

    @ViewBuilder
    private var listContent: some View {
        if let saveQueue, saveQueue.pendingCount > 0, model.selection == .all, !model.isSelecting {
            Section { PendingSavesRow(flusher: saveQueue) }
        }
        if model.showsCloseMatches {
            Section {
                ForEach(model.snippets) { row($0) }
            } header: {
                Text("No exact matches. Close matches:")
            }
        } else if model.pinnedSection.isEmpty {
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

    private func row(_ snippet: Snippet) -> some View {
        SnippetRow(snippet: snippet, showOwner: model.isReadOnly, search: model.parsedSearch.text, searchCode: model.searchCode,
                   expiry: settings.expiry(of: snippet, server: model.session.client?.server))
            .tag(snippet.id)
            .task { await model.loadMoreIfNeeded(current: snippet) }
            .contextMenu { SnippetActions(snippet: snippet, model: model) }
            #if os(iOS)
            .swipeActions(edge: .leading) {
                if !model.isReadOnly {
                Button { Task { await model.togglePin(snippet) } } label: {
                    Label(snippet.isPinned ? "Unpin" : "Pin", symbol: snippet.isPinned ? .pinOff : .pin)
                }.tint(.orange)
                Button { Task { await model.toggleFavorite(snippet) } } label: {
                    Label(snippet.isFavorite ? "Unfavorite" : "Favorite", symbol: snippet.isFavorite ? .starOff : .star)
                }.tint(.yellow)
                }
            }
            .swipeActions(edge: .trailing) {
                if model.isReadOnly {
                    EmptyView()
                } else if model.selection == .recycleBin {
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
            Button {
                Pasteboard.copy(allCode)
                model.recordCopy(snippet)
            } label: { Label("Copy Code", symbol: .copy) }
            SwiftUI.ShareLink(item: allCode) { Label("Share", symbol: .share) }
            if !model.isReadOnly {
            Divider()
            Button { Task { await model.setPublic(snippet, !snippet.isPublic) } } label: {
                Label(snippet.isPublic ? "Make Private" : "Make Public", symbol: snippet.isPublic ? .lock : .globe)
            }
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
                .snippetSearchSuggestions(model)
                .modifier(SearchFocus(request: model.searchFocusRequest))
        } else {
            content
        }
    }
}

/// Actions for the selected snippets, shown at the bottom in select mode.
struct BulkActionBar: View {
    let model: SnippetListModel
    @State private var categoryPrompt: CategoryPrompt?
    @State private var categoryName = ""

    private enum CategoryPrompt: Identifiable { case add, remove; var id: Self { self } }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(model.selectedIDs.isEmpty ? "Select snippets" : "\(model.selectedIDs.count) selected")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(model.selectedIDs.count == model.snippets.count ? "Deselect All" : "Select All") {
                    model.selectedIDs = model.selectedIDs.count == model.snippets.count ? [] : Set(model.snippets.map(\.id))
                }
                .font(.subheadline)
                if model.isBulkWorking { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 18) {
                if model.selection == .recycleBin {
                    Button { Task { await model.bulkRestore() } } label: { Label("Restore", symbol: .restore) }
                    Button(role: .destructive) { Task { await model.bulkDeleteForever() } } label: {
                        Label("Delete Forever", symbol: .trashForever)
                    }
                } else {
                    Menu {
                        Button { Task { await model.bulkSetPinned(true) } } label: { Label("Pin", symbol: .pin) }
                        Button { Task { await model.bulkSetPinned(false) } } label: { Label("Unpin", symbol: .pinOff) }
                    } label: { Label("Pin", symbol: .pin) }
                    Menu {
                        Button { Task { await model.bulkSetFavorite(true) } } label: { Label("Favorite", symbol: .star) }
                        Button { Task { await model.bulkSetFavorite(false) } } label: { Label("Unfavorite", symbol: .starOff) }
                    } label: { Label("Favorite", symbol: .star) }
                    Menu {
                        Button { categoryPrompt = .add } label: { Label("Add Category…", symbol: .tag) }
                        Button { categoryPrompt = .remove } label: { Label("Remove Category…", symbol: .minusCircle) }
                    } label: { Label("Category", symbol: .tag) }
                    Spacer()
                    Button(role: .destructive) { Task { await model.bulkRecycle() } } label: {
                        Label("Recycle", symbol: .trash)
                    }
                }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .disabled(model.selectedIDs.isEmpty || model.isBulkWorking)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 6)
        .alert(categoryPrompt == .remove ? "Remove Category" : "Add Category",
               isPresented: Binding(get: { categoryPrompt != nil }, set: { if !$0 { categoryPrompt = nil } })) {
            TextField("Category", text: $categoryName)
            Button("Cancel", role: .cancel) { categoryName = "" }
            Button(categoryPrompt == .remove ? "Remove" : "Add") {
                let name = categoryName, remove = categoryPrompt == .remove
                categoryName = ""
                Task { remove ? await model.bulkRemoveCategory(name) : await model.bulkAddCategory(name) }
            }
        } message: {
            Text("For the \(model.selectedIDs.count) selected snippets.")
        }
    }
}

extension View {
    /// Filter and value suggestions (`lang:`, `#tag`, `is:pinned`…) under the search field.
    public func snippetSearchSuggestions(_ model: SnippetListModel) -> some View {
        searchSuggestions {
            ForEach(model.searchSuggestions) { suggestion in
                Text(suggestion.title).searchCompletion(suggestion.completion)
            }
        }
    }
}
