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
    /// Why a drop couldn't be used (an image, an app, a folder…).
    @State private var dropProblem: String?
    @State private var scanning = false
    /// "Choose Photo" from the Scan button's menu (CP-84).
    @State private var scanningPhoto = false
    @State private var history = NavigationHistory(start: .all)
    @State private var toolbarID = WindowToolbarID(base: "main")
    /// Going Back/Forward into another section: the snippet to open once that section is loaded.
    @State private var restoredSnippet: Snippet.ID??
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    #if DEBUG && os(macOS)
    @MainActor private static var openedSecondWindow = false
    #endif

    init(services: AppServices) {
        self.services = services
        _sidebar = State(initialValue: SidebarModel(session: services.session))
        _list = State(initialValue: SnippetListModel(session: services.session, cache: services.cache,
                                         sortDefaults: AppEnvironment.sharedDefaults))
    }

    var body: some View {
        layout
        .environment(\.windowToolbarID, toolbarID.id)
        .task(id: sidebarSelection) {
            list.selection = sidebarSelection ?? .all
            // Only a change of section clears the open snippet; the first load must not drop one
            // opened from a widget, Spotlight or Handoff at launch.
            if loadedSection != nil, loadedSection != sidebarSelection { selectedSnippet = restoredSnippet ?? nil }
            restoredSnippet = nil
            loadedSection = sidebarSelection
            await list.refresh()
            if let id = selectedSnippet, !list.snippets.contains(where: { $0.id == id }) {
                _ = await list.reveal(id: id)
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-BCSelectFirst") { selectedSnippet = list.snippets.first?.id }
            #if os(macOS)
            // `-BCSecondWindow`: File → New Window once the first window has loaded (CP-82).
            if ProcessInfo.processInfo.arguments.contains("-BCSecondWindow"), !Self.openedSecondWindow {
                Self.openedSecondWindow = true
                try? await Task.sleep(for: .seconds(1))
                func find(_ menu: NSMenu?) -> NSMenuItem? {
                    for item in menu?.items ?? [] {
                        if item.title.hasPrefix("New") && item.title.hasSuffix("Window") { return item }
                        if let found = find(item.submenu) { return found }
                    }
                    return nil
                }
                if let item = find(NSApp.mainMenu), let index = item.menu?.index(of: item) {
                    item.menu?.performActionForItem(at: index)
                }
            }
            #endif
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
        .onChange(of: sidebarSelection) { _, section in history.visit(section: section ?? .all) }
        .onChange(of: selectedSnippet) { _, id in history.visit(snippet: id) }
        .onChange(of: services.settings.smartGroups, initial: true) {
            list.smartGroups = services.settings.smartGroups
            if case .smartGroup = list.selection { Task { await list.refresh() } }
        }
        .onChange(of: sidebar.languages + sidebar.categories, initial: true) {
            list.knownLanguages = sidebar.languages
            list.knownCategories = sidebar.categories
        }
        // Spotlight and the widgets follow the list once it settles: scrolling loads a page every
        // moment, and redoing both for each page made scrolling stutter. A change restarts the wait.
        .task(id: list.snippets) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if let server = services.session.client?.server { SpotlightIndexer.index(list.snippets, server: server) }
            await services.widgets.refresh()
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
        .task(id: AppNavigator.shared.pendingCaptureText) {
            guard let text = AppNavigator.shared.pendingCaptureText else { return }
            AppNavigator.shared.pendingCaptureText = nil
            startCapture(text)
        }
        .task(id: AppNavigator.shared.pendingScan) {
            guard AppNavigator.shared.pendingScan else { return }
            AppNavigator.shared.pendingScan = false
            scanning = true
        }
        .scanCodeFlow(isPresented: $scanning, choosingPhoto: $scanningPhoto) { startCapture($0, fromImage: true) }
        .alert("Can't Save That", isPresented: Binding(get: { dropProblem != nil }, set: { if !$0 { dropProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dropProblem ?? "")
        }
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
        // The login expired and the backup key took over: load what just failed again (CP-91).
        .onChange(of: services.session.backupKeySwitches) {
            Task { await list.refresh(); await sidebar.load() }
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
                          onNew: { startEditing(nil) }, onScan: { scanning = true }, onScanPhoto: { scanningPhoto = true },
                          onEdit: { startEditing($0) }, onCapture: { startCapture($0) },
                          onDrop: { handleDrop($0) })
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
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
                #endif
        } content: {
            SnippetListView(model: list, selection: $selectedSnippet)
                .safeAreaInset(edge: .bottom) {
                    if clipboard.hasText {
                        ClipboardBanner(watcher: clipboard) { startCapture($0) }
                    }
                }
                // Code files or text dropped here become a new snippet (CP-92).
                .onDrop(of: DropImport.types, isTargeted: nil) { providers in
                    handleDrop(providers)
                    return true
                }
                // Right-click the toolbar (Mac) or long-press it (iPad) to customise it.
                .toolbar(id: toolbarID.id) {
                    ToolbarItem(id: "back", placement: .navigation) {
                        Button { go(history.back()) } label: { Label("Back", symbol: .back) }
                            .toolbarIcon()
                            .disabled(!history.canGoBack)
                            .keyboardShortcut("[", modifiers: .command)
                            .help("Back (⌘[)")
                    }
                    ToolbarItem(id: "forward", placement: .navigation) {
                        Button { go(history.forward()) } label: { Label("Forward", symbol: .forward) }
                            .toolbarIcon()
                            .disabled(!history.canGoForward)
                            .keyboardShortcut("]", modifiers: .command)
                            .help("Forward (⌘])")
                    }
                    ToolbarItem(id: "scan", placement: .primaryAction) {
                        Button { scanning = true } label: { Label("Scan Code", symbol: .scan) }
                            .scanButtonMenu(camera: { scanning = true }, photo: { scanningPhoto = true })
                            .toolbarIcon()
                    }
                }
                // Stays in the bar when it's short of room (iPhone Duo inner display): before Scan, and Sort goes first.
                .toolbar(id: toolbarID.id, overflowPriority: .high) {
                    ToolbarItem(id: "new", placement: .primaryAction) {
                        Button { startEditing(nil) } label: { Label("New Snippet", symbol: .newSnippet) }
                            .primaryToolbarAction()
                    }
                }
                #if os(macOS)
                // Room for a row's language, tags and date on one line; it grows with the window.
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 560)
                #endif
        } detail: {
            Group {
                if let id = selectedSnippet {
                    SnippetDestination(id: id, list: list, services: services) { startEditing($0) }
                        .id(id)
                } else {
                    noSnippetSelected
                }
            }
            #if os(macOS)
            // Keeps the file header and code readable; the window's minimum width follows from it.
            .navigationSplitViewColumnWidth(min: 380, ideal: 600)
            #endif
        }
    }

    private var noSnippetSelected: some View {
        #if os(macOS)
        ContentUnavailableView("No Snippet Selected", symbol: .byteCache,
                               description: Text("Pick a snippet, or press ⌘N to create one."))
        #else
        // A button as well: iPhone Duo and iPad often have no keyboard, and in a tall window the list
        // is hidden behind the sidebar button. Kept off the fold when partially folded.
        ContentUnavailableView {
            Label("No Snippet Selected", symbol: .byteCache)
        } description: {
            Text("Pick a snippet, or create a new one.")
        } actions: {
            Button { startEditing(nil) } label: { Label("New Snippet", symbol: .newSnippet) }
                .buttonStyle(.borderedProminent)
        }
        .centeredAwayFromFold()
        #endif
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

    /// Shows a Back/Forward entry. The changes it makes match the history's current entry, so they
    /// aren't recorded again.
    private func go(_ entry: NavigationHistory.Entry?) {
        guard let entry else { return }
        if entry.section != (sidebarSelection ?? .all) { restoredSnippet = .some(entry.snippet) }
        sidebarSelection = entry.section
        selectedSnippet = entry.snippet
    }

    /// Dropped files or text (CP-92): one becomes a new snippet in the capture sheet (Smart Suggestions
    /// run there when they're on); several become one snippet with several files, in the editor.
    private func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            switch await DropImport.load(providers) {
            case .success(let files) where files.count == 1:
                startCapture(files[0].text, fileName: files[0].name)
            case .success(let files):
                startEditing(dropped: files)
            case .failure(let problem):
                dropProblem = DropImport.message(for: problem)
            }
        }
    }

    private func startEditing(dropped files: [DroppedFile]) {
        let model = SnippetEditorModel(existing: nil, session: services.session, detector: services.detector,
                                       suggester: services.settings.suggester, knownCategories: sidebar.categories)
        model.draft.fragments = files.map { FragmentDraft(fileName: $0.name ?? "", code: $0.text, language: "plaintext") }
        for index in model.draft.fragments.indices { model.codeChanged(fragment: index) }
        editor = model
    }

    private func startCapture(_ text: String, fromImage: Bool = false, fileName: String? = nil) {
        let session = services.session
        let model = CaptureModel(text: text, fileName: fileName, client: session.client, detector: services.detector,
                                 suggester: services.settings.suggester, knownCategories: sidebar.categories,
                                 queue: .shared) {
            session.handleUnauthorized()
        }
        model.readFromImage = fromImage
        capture = model
    }

    private func startEditing(_ snippet: Snippet?) {
        editor = SnippetEditorModel(existing: snippet, session: services.session, detector: services.detector,
                                    suggester: services.settings.suggester, knownCategories: sidebar.categories)
    }
}
