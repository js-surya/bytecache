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
    @State private var tab: PhoneTab = {
        #if DEBUG
        // `-BCTab search|library|pinned|favorites` opens on that tab (screenshots).
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-BCTab"),
           ProcessInfo.processInfo.arguments.indices.contains(i + 1) {
            switch ProcessInfo.processInfo.arguments[i + 1] {
            case "search": return .search
            case "library": return .library
            case "pinned": return .pinned
            case "favorites": return .favorites
            default: break
            }
        }
        #endif
        return .snippets
    }()
    @State private var pinned: SnippetListModel
    @State private var favorites: SnippetListModel
    @State private var library: SnippetListModel
    @State private var search: SnippetListModel
    @State private var pinnedSelection: Snippet.ID?
    @State private var favoritesSelection: Snippet.ID?
    @State private var librarySelection: Snippet.ID?
    @State private var searchSelection: Snippet.ID?
    @State private var libraryItem: SidebarItem?
    @State private var showingSettings = false
    @State private var searchPresented = false
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
            let m = SnippetListModel(session: services.session, cache: services.cache,
                                         sortDefaults: AppEnvironment.sharedDefaults)
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
                    Group {
                        if search.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            ContentUnavailableView("Search Snippets", symbol: .braces,
                                                   description: Text(services.settings.searchInCode
                                                        ? "Find snippets by title, description or code."
                                                        : "Find snippets by title or description. To search inside code too, turn on Search Inside Code in Settings."))
                        } else {
                            list(search, selection: $searchSelection)
                        }
                    }
                    .navigationTitle("Search")
                    .toolbar { settingsButton }
                }
                // Only the Search tab searches; tapping the tab opens the field with the keyboard.
                .searchable(text: $search.searchText, isPresented: $searchPresented,
                            placement: .toolbar, prompt: "Search snippets")
                .onChange(of: search.searchText) { search.searchTextChanged() }
                .onChange(of: services.settings.searchInCode, initial: true) {
                    search.searchCode = services.settings.searchInCode
                    if !search.searchText.isEmpty { Task { await search.refresh() } }
                }
            }
        }
        .onChange(of: tab) { searchPresented = tab == .search }
        .onAppear {
            if tab == .search { searchPresented = true }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-BCShowSettings") { showingSettings = true }
            #endif
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(session: services.session)
                    .toolbar { Button("Done") { showingSettings = false } }
            }
            .appSettingsStyle(services.settings)
        }
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

    /// Settings from every tab, top left — the usual iPhone spot for account and settings.
    @ToolbarContentBuilder
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showingSettings = true } label: { Label("Settings", symbol: .settings) }
        }
    }

    private func list(_ model: SnippetListModel, selection: Binding<Snippet.ID?>) -> some View {
        SnippetListView(model: model, selection: selection, showsSearchField: false)
            .toolbar {
                settingsButton
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: onScan) { Label("Scan Code", symbol: .scan) }
                    Button(action: onNew) { Label("New Snippet", symbol: .newSnippet) }
                }
            }
            .navigationDestination(item: selection) { id in
                SnippetDestination(id: id, list: model, services: services, onEdit: onEdit)
            }
    }
}
#endif
