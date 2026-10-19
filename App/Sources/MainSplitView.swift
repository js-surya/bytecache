import CoreSpotlight
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
    @State private var capture: CaptureModel?
    @State private var clipboard = ClipboardWatcher()
    @State private var clipboardEmpty = false
    @State private var scanning = false
    @Environment(\.scenePhase) private var scenePhase

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
                .safeAreaInset(edge: .bottom) {
                    if clipboard.hasText {
                        ClipboardBanner(watcher: clipboard) { startCapture($0) }
                    }
                }
                .dropDestination(for: String.self) { items, _ in
                    let text = items.joined(separator: "\n")
                    guard text.contains(where: { !$0.isWhitespace }) else { return false }
                    startCapture(text)
                    return true
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { scanning = true } label: { Label("Scan Code", systemImage: "camera.viewfinder") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { startEditing(nil) } label: { Label("New Snippet", systemImage: "square.and.pencil") }
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
            if ProcessInfo.processInfo.arguments.contains("-BCNewSnippet"), editor == nil { startEditing(nil) }
            #endif
        }
        .userActivity(SnippetActivity.type, isActive: services.settings.handoffEnabled && selected != nil) { activity in
            guard let snippet = selected, let server = services.session.client?.server else { return }
            activity.title = snippet.title
            activity.userInfo = SnippetActivity.userInfo(server: server, snippetID: snippet.id)
            activity.webpageURL = SnippetActivity.webURL(server: server, snippetID: snippet.id)
            activity.isEligibleForHandoff = true
        }
        .onAppear { clipboard.check() }
        .onChange(of: list.snippets) {
            if let server = services.session.client?.server { SpotlightIndexer.index(list.snippets, server: server) }
            Task { await services.widgets.refresh() }
        }
        .task(id: AppNavigator.shared.pendingClipboardCapture) {
            guard AppNavigator.shared.pendingClipboardCapture else { return }
            AppNavigator.shared.pendingClipboardCapture = false
            if let text = Pasteboard.string(), text.contains(where: { !$0.isWhitespace }) {
                startCapture(text)
            } else {
                clipboardEmpty = true
            }
        }
        .task(id: AppNavigator.shared.pendingScan) {
            guard AppNavigator.shared.pendingScan else { return }
            AppNavigator.shared.pendingScan = false
            scanning = true
        }
        .scanCodeFlow(isPresented: $scanning) { startCapture($0) }
        .alert("Nothing to Save", isPresented: $clipboardEmpty) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy some code first, then try again.")
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(Int.init) {
                AppNavigator.shared.pendingSnippetID = id
            }
        }
        .task(id: AppNavigator.shared.pendingSnippetID) {
            guard let id = AppNavigator.shared.pendingSnippetID else { return }
            AppNavigator.shared.pendingSnippetID = nil
            if await list.reveal(id: id) { selectedSnippet = id }
        }
        .onChange(of: scenePhase) { if scenePhase == .active { clipboard.check() } }
        .focusedSceneValue(\.snippetCommands, commands)
        .sheet(item: $capture) { model in
            NavigationStack {
                CaptureSheet(model: model, knownCategories: sidebar.categories) { saved in
                    if let saved {
                        list.didSave(saved)
                        selectedSnippet = saved.id
                        Task { await sidebar.load() }
                    }
                    capture = nil
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 520)
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

    private var selected: Snippet? {
        selectedSnippet.flatMap { id in list.snippets.first { $0.id == id } }
    }

    private var commands: SnippetCommandActions {
        let snippet = selected
        return SnippetCommandActions(
            newSnippet: { startEditing(nil) },
            refresh: { Task { await list.refresh(); await sidebar.load() } },
            focusSearch: { list.searchFocusRequest += 1 },
            edit: snippet.map { s in { startEditing(s) } },
            copyCode: snippet.map { s in { Pasteboard.copy(s.fragments.sorted { $0.position < $1.position }.map(\.code).joined(separator: "\n\n")) } },
            recycle: snippet.flatMap { s in list.selection == .recycleBin ? nil : { Task { await list.recycle(s) } } }
        )
    }

    private func startCapture(_ text: String) {
        let session = services.session
        capture = CaptureModel(text: text, client: session.client, detector: services.detector,
                               suggester: services.settings.suggester, knownCategories: sidebar.categories) {
            session.handleUnauthorized()
        }
    }

    private func startEditing(_ snippet: Snippet?) {
        editor = SnippetEditorModel(existing: snippet, session: services.session, detector: services.detector,
                                    suggester: services.settings.suggester, knownCategories: sidebar.categories)
    }
}
