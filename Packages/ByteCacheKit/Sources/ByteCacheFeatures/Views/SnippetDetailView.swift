import ByteCacheCore
import SwiftUI

public struct SnippetDetailView: View {
    let snippet: Snippet
    let list: SnippetListModel?
    let onEdit: () -> Void

    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @State private var exporting = false
    @State private var exportFile: ExportFile?
    @State private var exportMessage: String?
    @State private var sharingLinks = false
    @State private var explaining = false
    /// The file shown when files are tabs (nil: the first).
    @State private var selectedFile: Int?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow
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
        .toolbar(id: "main") {
            if let list, !readOnly {
                ToolbarItem(id: "pin", placement: .primaryAction) {
                    Button { Task { await list.togglePin(snippet) } } label: {
                        Label(snippet.isPinned ? "Unpin" : "Pin", symbol: snippet.isPinned ? .pinFill : .pin)
                            .foregroundStyle(snippet.isPinned ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                    }
                }
                ToolbarItem(id: "favorite", placement: .primaryAction) {
                    Button { Task { await list.toggleFavorite(snippet) } } label: {
                        Label(snippet.isFavorite ? "Unfavorite" : "Favorite", symbol: snippet.isFavorite ? .starFill : .star)
                            .foregroundStyle(snippet.isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tint))
                    }
                }
            }
            ToolbarItem(id: "wrap", placement: .primaryAction) {
                Toggle(isOn: Bindable(settings).wrapLines) {
                    Label("Wrap Long Lines", symbol: .wrapLines)
                }
                .toggleStyle(.button)
                .help("Wrap Long Lines")
            }
            if settings.suggestionsEnabled, let explainer = SnippetSuggesters.explainer() {
                ToolbarItem(id: "explain", placement: .primaryAction) {
                    Button { explaining = true } label: { Label("Explain", symbol: .sparkles) }
                        .sheet(isPresented: $explaining) {
                            NavigationStack {
                                ExplainSheet(model: ExplainModel(explainer: explainer),
                                             snippet: (allCode, fragments.first?.language ?? "plaintext", snippet.title))
                            }
                        }
                }
            }
            ToolbarItem(id: "share", placement: .primaryAction) {
                SwiftUI.ShareLink(item: allCode)
            }
            if let list, !readOnly {
                ToolbarItem(id: "share-link", placement: .primaryAction) {
                    Button { sharingLinks = true } label: { Label("Share Link", symbol: .link) }
                        .sheet(isPresented: $sharingLinks) {
                            NavigationStack {
                                ShareLinksView(model: ShareLinksModel(session: list.session, snippetID: snippet.id), title: snippet.title)
                            }
                        }
                }
            }
            ToolbarItem(id: "save", placement: .primaryAction) {
                saveButton
            }
            if showsOpenInWindow && supportsMultipleWindows {
                ToolbarItem(id: "window", placement: .primaryAction) {
                    Button { openWindow(value: snippet.id) } label: {
                        Label("Open in New Window", symbol: .newWindow)
                    }
                }
            }
            if !readOnly {
                ToolbarItem(id: "edit", placement: .primaryAction) {
                    Button(action: onEdit) { Label("Edit", symbol: .edit) }
                }
            }
        }
        .logScreen("Snippet")
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
