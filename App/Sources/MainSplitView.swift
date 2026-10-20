import CoreSpotlight
import SwiftUI
import ByteCacheCore
import ByteCacheFeatures

/// Sidebar | list | detail. Collapses to a stack on iPhone.
struct MainSplitView: View {
    let services: AppServices
    @State private var sidebar: SidebarModel
    @State private var list: SnippetListModel
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var selectedSnippet: Snippet.ID?
    @State private var loadedSection: SidebarItem??
    @State private var editor: SnippetEditorModel?
    @State private var capture: CaptureModel?
    @State private var clipboard = ClipboardWatcher()
    @State private var clipboardEmpty = false
    @State private var scanning = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(services: AppServices) {
        self.services = services
        _sidebar = State(initialValue: SidebarModel(session: services.session))
        _list = State(initialValue: SnippetListModel(session: services.session, cache: services.cache,
                                         sortDefaults: AppEnvironment.sharedDefaults))
    }

    var body: some View {
        layout
        .task(id: sidebarSelection) {
            list.selection = sidebarSelection ?? .all
            // Only a change of section clears the open snippet; the first load must not drop one
            // opened from a widget, Spotlight or Handoff at launch.
            if loadedSection != nil, loadedSection != sidebarSelection { selectedSnippet = nil }
            loadedSection = sidebarSelection
            await list.refresh()
            if let id = selectedSnippet, !list.snippets.contains(where: { $0.id == id }) {
                _ = await list.reveal(id: id)
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-BCSelectFirst") { selectedSnippet = list.snippets.first?.id }
            if ProcessInfo.processInfo.arguments.contains("-BCNewSnippet"), editor == nil {
                startEditing(nil)
                if let code = ProcessInfo.processInfo.environment["BC_DEBUG_CODE"], let editor {
                    editor.draft.fragments[0].code = code
                    editor.codeChanged(fragment: 0)
                }
            }
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
        .onChange(of: services.settings.smartGroups, initial: true) {
            list.smartGroups = services.settings.smartGroups
            if case .smartGroup = list.selection { Task { await list.refresh() } }
        }
        .onChange(of: sidebar.languages + sidebar.categories, initial: true) {
            list.knownLanguages = sidebar.languages
            list.knownCategories = sidebar.categories
        }
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
            // Clear the request only afterwards: changing the task's id cancels the running fetch.
            if await list.reveal(id: id) { selectedSnippet = id }
            AppNavigator.shared.pendingSnippetID = nil
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            clipboard.check()
            Task { await services.saveQueue.flush() }
        }
        .task {
            // Expired snippets go to the Recycle Bin while ByteCache is open.
            while !Task.isCancelled {
                await ExpirySweeper.sweep(settings: services.settings, list: list)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .task {
            services.saveQueue.startMonitoring()
            await services.saveQueue.flush()
        }
        .onChange(of: services.saveQueue.uploadedGeneration) {
            Task { await list.refresh(); await sidebar.load() }
        }
        .environment(services.saveQueue)
        .focusedSceneValue(\.snippetCommands, commands)
        .sheet(item: $capture) { model in
            NavigationStack {
                CaptureSheet(model: model, knownCategories: sidebar.categories, onQueued: {
                    services.saveQueue.refresh()
                    capture = nil
                }) { saved in
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

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if #available(iOS 26.1, *), horizontalSizeClass == .compact {
            PhoneTabsView(services: services, all: list, sidebar: sidebar, clipboard: clipboard,
                          allSelection: $selectedSnippet,
                          onNew: { startEditing(nil) }, onScan: { scanning = true },
                          onEdit: { startEditing($0) }, onCapture: { startCapture($0) })
        } else {
            splitView
        }
        #else
        splitView
        #endif
    }

    private var splitView: some View {
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
                        Button { scanning = true } label: { Label("Scan Code", symbol: .scan) }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { startEditing(nil) } label: { Label("New Snippet", symbol: .newSnippet) }
                    }
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
                #endif
        } detail: {
            if let id = selectedSnippet {
                SnippetDestination(id: id, list: list, services: services) { startEditing($0) }
                    .id(id)
            } else {
                ContentUnavailableView("No Snippet Selected", symbol: .braces,
                                       description: Text("Pick a snippet, or press ⌘N to create one."))
            }
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
            copyCode: snippet.map { s in {
                Pasteboard.copy(s.fragments.sorted { $0.position < $1.position }.map(\.code).joined(separator: "\n\n"))
                list.recordCopy(s)
            } },
            recycle: snippet.flatMap { s in list.selection == .recycleBin ? nil : { Task { await list.recycle(s) } } }
        )
    }

    private func startCapture(_ text: String) {
        let session = services.session
        capture = CaptureModel(text: text, client: session.client, detector: services.detector,
                               suggester: services.settings.suggester, knownCategories: sidebar.categories,
                               queue: .shared) {
            session.handleUnauthorized()
        }
    }

    private func startEditing(_ snippet: Snippet?) {
        editor = SnippetEditorModel(existing: snippet, session: services.session, detector: services.detector,
                                    suggester: services.settings.suggester, knownCategories: sidebar.categories)
    }
}
