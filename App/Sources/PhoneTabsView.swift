#if os(iOS)
import SwiftUI
import ByteCatchCore
import ByteCatchFeatures

/// iPhone layout on iOS 26.1+: a Liquid Glass tab bar at the bottom with Search on the right.
/// Scrolling down shrinks the bar to the current tab and the search button.
@available(iOS 26.1, *)
struct PhoneTabsView: View {
    enum PhoneTab: Hashable { case snippets, pinned, favorites, library, search }

    let services: AppServices
    let all: SnippetListModel
    let sidebar: SidebarModel
    let clipboard: ClipboardWatcher
    let onNew: () -> Void
    let onScan: () -> Void
    let onEdit: (Snippet) -> Void
    let onCapture: (String) -> Void

    @Binding var allSelection: Snippet.ID?
    @State private var tab = PhoneTab.snippets
    @State private var pinned: SnippetListModel
    @State private var favorites: SnippetListModel
    @State private var library: SnippetListModel
    @State private var search: SnippetListModel
    @State private var pinnedSelection: Snippet.ID?
    @State private var favoritesSelection: Snippet.ID?
    @State private var librarySelection: Snippet.ID?
    @State private var searchSelection: Snippet.ID?
    @State private var libraryItem: SidebarItem?
    @Environment(\.iconStyle) private var iconStyle

    init(services: AppServices, all: SnippetListModel, sidebar: SidebarModel, clipboard: ClipboardWatcher,
         allSelection: Binding<Snippet.ID?>, onNew: @escaping () -> Void, onScan: @escaping () -> Void,
         onEdit: @escaping (Snippet) -> Void, onCapture: @escaping (String) -> Void) {
        self.services = services
        self.all = all
        self.sidebar = sidebar
        self.clipboard = clipboard
        _allSelection = allSelection
        self.onNew = onNew
        self.onScan = onScan
        self.onEdit = onEdit
        self.onCapture = onCapture
        func model(_ item: SidebarItem) -> SnippetListModel {
            let m = SnippetListModel(session: services.session, cache: services.cache)
            m.selection = item
            return m
        }
        _pinned = State(initialValue: model(.pinned))
        _favorites = State(initialValue: model(.favorites))
        _library = State(initialValue: model(.all))
        _search = State(initialValue: model(.all))
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(value: PhoneTab.snippets) {
                stack(all, selection: $allSelection)
            } label: { tabLabel("Snippets", .braces) }

            Tab(value: PhoneTab.pinned) {
                stack(pinned, selection: $pinnedSelection)
            } label: { tabLabel("Pinned", .pin) }

            Tab(value: PhoneTab.favorites) {
                stack(favorites, selection: $favoritesSelection)
            } label: { tabLabel("Favorites", .star) }

            Tab(value: PhoneTab.library) {
                NavigationStack {
                    SidebarView(model: sidebar, selection: $libraryItem, session: services.session)
                        .navigationDestination(item: $libraryItem) { item in
                            list(library, selection: $librarySelection)
                                .task(id: item) {
                                    library.selection = item
                                    await library.refresh()
                                }
                        }
                }
            } label: { tabLabel("Library", .allSnippets) }

            Tab(value: PhoneTab.search, role: .search) {
                NavigationStack {
                    list(search, selection: $searchSelection, searchable: true)
                        .task { if search.snippets.isEmpty { await search.refresh() } }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: clipboard.hasText) {
            HStack {
                Icon(.clipboard)
                Text("Save copied code?").font(.subheadline)
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    let text = strings.joined(separator: "\n")
                    Task { @MainActor in
                        clipboard.dismiss()
                        onCapture(text)
                    }
                }
                .labelStyle(.iconOnly)
                Button { clipboard.dismiss() } label: { Icon(.close) }
                    .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal)
        }
    }

    /// Tab bar items take a plain image, so build it from the chosen icon style.
    private func tabLabel(_ title: String, _ symbol: AppSymbol) -> some View {
        Label { Text(title) } icon: { symbol.image(iconStyle) }
    }

    private func stack(_ model: SnippetListModel, selection: Binding<Snippet.ID?>) -> some View {
        NavigationStack {
            list(model, selection: selection)
                .task { if model.snippets.isEmpty { await model.refresh() } }
        }
    }

    private func list(_ model: SnippetListModel, selection: Binding<Snippet.ID?>, searchable: Bool = false) -> some View {
        SnippetListView(model: model, selection: selection, showsSearchField: searchable)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: onScan) { Label("Scan Code", symbol: .scan) }
                    Button(action: onNew) { Label("New Snippet", symbol: .newSnippet) }
                }
            }
            .navigationDestination(item: selection) { id in
                if let snippet = model.snippets.first(where: { $0.id == id }) {
                    SnippetDetailView(snippet: snippet, list: model) { onEdit(snippet) }
                }
            }
    }
}
#endif
