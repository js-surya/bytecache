import ByteCacheCore
import SwiftUI

public struct SnippetDetailView: View {
    let snippet: Snippet
    let list: SnippetListModel?
    let onEdit: () -> Void

    @Environment(\.windowToolbarID) private var windowToolbarID
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @State private var exporting = false
    @State private var exportFile: ExportFile?
    @State private var exportMessage: String?
    @State private var sharingLinks = false
    /// Explain's sheet is open: continuing the saved chat, or starting a new one.
    @State private var explaining: ExplainStart?
    /// The file shown when files are tabs (nil: the first).
    @State private var selectedFile: Int?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @Environment(AINoteStore.self) private var aiNotes: AINoteStore?
    @Environment(ExplainChatStore.self) private var explainChats: ExplainChatStore?
    let showsOpenInWindow: Bool

    public init(snippet: Snippet, list: SnippetListModel?, showsOpenInWindow: Bool = true, onEdit: @escaping () -> Void) {
        self.snippet = snippet
        self.list = list
        self.showsOpenInWindow = showsOpenInWindow
        self.onEdit = onEdit
    }

    private var readOnly: Bool { list?.isReadOnly ?? false }

    /// `-BCSuggestTitlePreview`: offer Suggest Title on any snippet (screenshots; Debug builds only).
    private static var previewSuggestTitle: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-BCSuggestTitlePreview")
        #else
        false
        #endif
    }

    private var wholeSnippet: ExportFile {
        ExportFile(wrapper: SnippetExport.fileWrapper(for: snippet), contentType: SnippetExport.contentType(for: snippet))
    }

    private func save(_ choice: ExportChoice) {
        exportFile = choice.export()
        exporting = true
    }

    private var fragments: [Fragment] { snippet.fragments.sorted { $0.position < $1.position } }
    private var allCode: String { fragments.map(\.code).joined(separator: "\n\n") }

    /// Mac and iPad (not iPhone or iPad split narrow): files as tabs, with a status bar.
    private var wide: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }
    private var usesTabs: Bool { wide && fragments.count > 1 }

    /// AI Notes belong to the signed-in server's snippets (not someone else's public ones).
    private var noteServer: String? { readOnly ? nil : list?.session.client?.server.cacheKey }
    private var canExplain: Bool { settings.explainer != nil }
    private var shownFile: Fragment? {
        fragments.first { $0.id == selectedFile } ?? fragments.first
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snippet.title.isEmpty ? "Untitled snippet" : snippet.title)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    if snippet.needsTitle || Self.previewSuggestTitle, let list, !readOnly, let suggester = settings.suggester {
                        SuggestTitleBar(snippet: snippet, suggester: suggester, list: list)
                    }
                    if snippet.isPinned || snippet.isFavorite || snippet.isPublic {
                        HStack(spacing: 8) {
                            if snippet.isPinned { StatusChip(title: "Pinned", symbol: .pinFill, color: .orange) }
                            if snippet.isFavorite { StatusChip(title: "Favorite", symbol: .starFill, color: .yellow) }
                            if snippet.isPublic { StatusChip(title: "Public", symbol: .globe, color: .blue) }
                        }
                    }
                    if let expiry = settings.expiry(of: snippet, server: list?.session.client?.server) {
                        ExpiryBadge(date: expiry)
                    }
                    if readOnly, let owner = snippet.username {
                        Text("Shared publicly by \(owner)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !snippet.description.isEmpty {
                        Text(snippet.description).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if !snippet.categories.isEmpty {
                        HStack {
                            ForEach(snippet.categories, id: \.self) { category in
                                Text("#\(category)")
                                    .font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.tint.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
                if usesTabs, let shownFile {
                    VStack(alignment: .leading, spacing: 8) {
                        FileTabStrip(fragments: fragments, selection: $selectedFile)
                        FragmentCard(fragment: shownFile, snippetTitle: snippet.title) { list?.recordCopy(snippet) }
                            .id(shownFile.id)
                    }
                } else {
                    ForEach(fragments) { fragment in
                        FragmentCard(fragment: fragment, snippetTitle: snippet.title) { list?.recordCopy(snippet) }
                    }
                }
                if let server = noteServer, let note = aiNotes?.note(server: server, snippetID: snippet.id) {
                    AINoteCard(note: note, code: allCode, canExplainAgain: canExplain,
                               followUps: max(0, (explainChats?.chat(server: server, snippetID: snippet.id)?.messages.count ?? 1) - 1)) {
                        explaining = .fresh
                    } onContinueChat: {
                        explaining = .resume
                    } onDelete: {
                        withAnimation {
                            aiNotes?.delete(server: server, snippetID: snippet.id)
                            explainChats?.delete(server: server, snippetID: snippet.id)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if wide, let shownFile {
                SnippetStatusBar(fragment: shownFile) { list?.recordCopy(snippet) }
            }
        }
        .onChange(of: snippet.id) { selectedFile = nil }
        .navigationTitle(snippet.title)
        .fileExporter(isPresented: $exporting,
                      document: SnippetFileDocument(wrapper: (exportFile ?? wholeSnippet).wrapper),
                      contentType: (exportFile ?? wholeSnippet).contentType,
                      defaultFilename: (exportFile ?? wholeSnippet).filename) { result in
            if case .failure(let error) = result { exportMessage = error.localizedDescription }
        }
        .alert("Couldn't Save", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Right-click the toolbar (Mac) or long-press it (iPad) to choose and reorder these.
        .toolbar(id: windowToolbarID) {
            if let list, !readOnly {
                ToolbarItem(id: "pin", placement: .primaryAction) {
                    // The colour goes on the button: in toolbars its tint wins over the label's style.
                    Button { Task { await list.togglePin(snippet) } } label: {
                        Label(snippet.isPinned ? "Unpin" : "Pin", symbol: snippet.isPinned ? .pinFill : .pin)
                    }
                    .tint(snippet.isPinned ? .orange : .primary)
                }
                ToolbarItem(id: "favorite", placement: .primaryAction) {
                    Button { Task { await list.toggleFavorite(snippet) } } label: {
                        Label(snippet.isFavorite ? "Unfavorite" : "Favorite", symbol: snippet.isFavorite ? .starFill : .star)
                    }
                    .tint(snippet.isFavorite ? .yellow : .primary)
                }
            }
            ToolbarItem(id: "wrap", placement: .primaryAction) {
                Toggle(isOn: Bindable(settings).wrapLines) {
                    Label("Wrap Long Lines", symbol: .wrapLines)
                }
                .toggleStyle(.button)
                .toolbarIcon()
                .help("Wrap Long Lines")
            }
            if let explainer = settings.explainer {
                ToolbarItem(id: "explain", placement: .primaryAction) {
                    Button { explaining = .resume } label: { Label("Explain", symbol: .sparkles) }
                        .toolbarIcon()
                        .sheet(item: $explaining) { start in
                            NavigationStack {
                                ExplainSheet(model: explainChat(explainer, start: start))
                            }
                        }
                }
            }
            ToolbarItem(id: "share", placement: .primaryAction) {
                SwiftUI.ShareLink(item: allCode).toolbarIcon()
            }
            if let list, !readOnly {
                ToolbarItem(id: "share-link", placement: .primaryAction) {
                    Button { sharingLinks = true } label: { Label("Share Link", symbol: .link) }
                        .toolbarIcon()
                        .sheet(isPresented: $sharingLinks) {
                            NavigationStack {
                                ShareLinksView(model: ShareLinksModel(session: list.session, snippetID: snippet.id), title: snippet.title)
                            }
                        }
                }
            }
            ToolbarItem(id: "save", placement: .primaryAction) {
                saveButton.toolbarIcon()
            }
            if showsOpenInWindow && supportsMultipleWindows {
                ToolbarItem(id: "window", placement: .primaryAction) {
                    Button { openWindow(value: snippet.id) } label: {
                        Label("Open in New Window", symbol: .newWindow)
                    }
                    .toolbarIcon()
                }
            }
            if !readOnly {
                ToolbarItem(id: "edit", placement: .primaryAction) {
                    Button(action: onEdit) { Label("Edit", symbol: .edit) }.toolbarIcon()
                }
            }
        }
        #if DEBUG
        // `-BCExplain`: opens Explain's chat for the opened snippet.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-BCExplain"), canExplain else { return }
            try? await Task.sleep(for: .seconds(1))
            explaining = .resume
        }
        // `-BCAINotePreview`: a sample AI Note for older code, so the card and its "code changed" note show.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-BCAINotePreview"), let server = noteServer,
                  aiNotes?.note(server: server, snippetID: snippet.id) == nil else { return }
            aiNotes?.save("""
            Defines a small **Greeter** type and prints a greeting.

            - `Greeter` stores a `name` and builds `"Hello, <name>!"` in `greet()`.
            - The last line creates one for "ByteCache" and prints the result.
            - Nothing risky: no files, network or secrets.
            """, code: allCode + "\n// older version", server: server, snippetID: snippet.id, date: Date().addingTimeInterval(-3_600))
        }
        #endif
        .logScreen("Snippet")
    }

    enum ExplainStart: Identifiable {
        case resume, fresh
        var id: Self { self }
    }

    /// Explain's chat (CP-101): the saved one, or one that starts from the AI Note (made on another
    /// device, or before chats), or a new explanation.
    private func explainChat(_ explainer: any SnippetExplainer, start: ExplainStart) -> ExplainChatModel {
        let server = noteServer
        let saved = start == .fresh ? nil : server.flatMap { explainChats?.chat(server: $0, snippetID: snippet.id) }
        let note = start == .fresh ? nil : server.flatMap { aiNotes?.note(server: $0, snippetID: snippet.id) }
        var messages = saved?.messages ?? []
        var codeChanged = saved?.isStale(for: allCode) ?? false
        if let note, saved.map({ note.created > $0.updated && $0.messages.first?.text != note.text }) ?? true {
            // A newer explanation (from another device) starts a new chat.
            messages = [ChatMessage(role: .assistant, text: note.text,
                                    author: note.author ?? AIProvider.appleIntelligence.name, date: note.created)]
            codeChanged = note.isStale(for: allCode)
        }
        let model = ExplainChatModel(explainer: explainer, provider: settings.aiProvider, author: settings.aiAuthor,
                                     code: allCode, language: fragments.first?.language ?? "plaintext",
                                     title: snippet.title, messages: messages, codeChanged: codeChanged)
        let code = allCode, id = snippet.id, author = settings.aiAuthor
        model.onExplained = { [aiNotes] text in
            if let server { aiNotes?.save(text, code: code, server: server, snippetID: id, author: author) }
        }
        model.onChange = { [explainChats] messages in
            if let server { explainChats?.save(messages, code: code, server: server, snippetID: id) }
        }
        return model
    }

    @ViewBuilder
    private var saveButton: some View {
        let choices = SnippetExport.choices(for: snippet)
        if choices.count > 1 {
            Menu {
                ForEach(choices) { choice in
                    Button(choice.id == "all" ? "\(choice.title)…" : choice.title) { save(choice) }
                    if choice.id == "all" { Divider() }
                }
            } label: {
                Label("Save", symbol: .download)
            }
        } else if let only = choices.first {
            Button { save(only) } label: { Label("Save File…", symbol: .download) }
        }
    }
}

/// "Pinned" / "Favorite" label under a snippet's title.
struct StatusChip: View {
    let title: String
    let symbol: AppSymbol
    let color: Color

    var body: some View {
        Label { Text(title) } icon: { Icon(symbol) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}
