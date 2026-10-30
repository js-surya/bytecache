import ByteCacheCore
import Observation
import SwiftUI

/// The global keyboard shortcut that opens Quick Search on the Mac.
public enum QuickSearchShortcut: String, CaseIterable, Identifiable, Sendable {
    case off, controlOptionSpace, shiftCommandSpace, controlOptionCommandSpace

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "None"
        case .controlOptionSpace: "⌃⌥Space"
        case .shiftCommandSpace: "⇧⌘Space"
        case .controlOptionCommandSpace: "⌃⌥⌘Space"
        }
    }
}

/// Quick Search: find a snippet and copy it (or open it) without switching to ByteCache.
@MainActor @Observable
public final class QuickSearchModel {
    public let list: SnippetListModel
    /// Index of the highlighted result.
    public var highlighted = 0

    public init(list: SnippetListModel) {
        self.list = list
    }

    public var results: [Snippet] { Array(list.snippets.prefix(Self.maxResults)) }
    public var highlightedSnippet: Snippet? { results.indices.contains(highlighted) ? results[highlighted] : nil }

    static let maxResults = 30

    /// Moves the highlight, staying inside the results.
    public func move(by step: Int) {
        guard !results.isEmpty else { highlighted = 0; return }
        highlighted = min(max(highlighted + step, 0), results.count - 1)
    }

    /// The list shown before anything is typed (Settings → Search); a search looks everywhere.
    private var start: QuickSearchStart = .recent

    public func searchChanged() {
        highlighted = 0
        let searching = list.searchText.contains { !$0.isWhitespace }
        list.selection = searching ? .all : start.sidebarItem
        list.searchTextChanged()
    }

    /// Fresh results each time the panel opens, from the start list unless a search is kept.
    public func opened(start: QuickSearchStart = .recent, clearSearch: Bool = true) async {
        self.start = start
        highlighted = 0
        if clearSearch { list.searchText = "" }
        let searching = list.searchText.contains { !$0.isWhitespace }
        list.selection = searching ? .all : start.sidebarItem
        await list.refresh()
    }

    /// Every file of the snippet, in order — what the Copy command copies.
    public static func code(of snippet: Snippet) -> String {
        snippet.fragments.sorted { $0.position < $1.position }.map(\.code).joined(separator: "\n\n")
    }

    public func copy(_ snippet: Snippet) {
        Pasteboard.copy(Self.code(of: snippet))
        list.recordCopy(snippet)
    }
}

#if os(macOS)
/// The Quick Search window: search field and results. ↑/↓ move; Return and ⌥Return copy, paste into the
/// previous app or open, as chosen in Settings (CP-68); ⌘Return opens; Esc closes.
public struct QuickSearchView: View {
    @Bindable var model: QuickSearchModel
    let lock: AppLockModel
    /// Nil: the standard Quick Search panel size. The menu bar passes the size chosen in Settings.
    let size: CGSize?
    let onClose: () -> Void
    @FocusState private var fieldFocused: Bool
    @Environment(AppSettings.self) private var settings

    public init(model: QuickSearchModel, lock: AppLockModel, size: CGSize? = nil, onClose: @escaping () -> Void) {
        self.model = model
        self.lock = lock
        self.size = size
        self.onClose = onClose
    }

    public var body: some View {
        @Bindable var list = model.list
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Icon(.search).foregroundStyle(.secondary)
                TextField("Search snippets", text: $list.searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit { choose(option: NSEvent.modifierFlags.contains(.option)) }
                    .disabled(lock.isLocked)
            }
            .padding(12)
            Divider()
            content
        }
        .frame(width: size?.width ?? 560, height: size?.height ?? 480)
        .onChange(of: model.list.searchText) { model.searchChanged() }
        .onKeyPress(.upArrow) { model.move(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.move(by: 1); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) || press.modifiers.contains(.option),
                  model.highlightedSnippet != nil else { return .ignored }
            choose(option: press.modifiers.contains(.option), command: press.modifiers.contains(.command))
            return .handled
        }
        .task {
            fieldFocused = true
            model.list.searchCode = settings.searchInCode
            if !lock.isLocked {
                await model.opened(start: settings.quickSearchStart, clearSearch: settings.quickSearchClearsOnOpen)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if lock.isLocked {
            ContentUnavailableView("ByteCache is Locked", symbol: .lock,
                                   description: Text("Open ByteCache to unlock it."))
                .frame(maxHeight: .infinity)
        } else if model.results.isEmpty {
            if model.list.isLoading {
                LoadingMark().frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView(model.list.searchText.isEmpty ? "No Snippets" : "No Results", symbol: .search)
                    .frame(maxHeight: .infinity)
            }
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, snippet in
                        SnippetRow(snippet: snippet, search: model.list.parsedSearch.text, searchCode: model.list.searchCode)
                            .padding(.horizontal, 4)
                            .listRowBackground(index == model.highlighted ? Color.accentColor.opacity(0.18) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.highlighted = index
                                choose(option: NSEvent.modifierFlags.contains(.option))
                            }
                            .id(snippet.id)
                    }
                }
                .listStyle(.plain)
                .onChange(of: model.highlighted) { _, index in
                    if let id = model.highlightedSnippet?.id { proxy.scrollTo(id) }
                }
            }
            if let snippet = model.highlightedSnippet {
                Divider()
                preview(snippet)
            }
            Divider()
            Text(QuickSearchAction.hint(settings: settings))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }

    /// The highlighted snippet's first file, so you can check it before choosing.
    private func preview(_ snippet: Snippet) -> some View {
        let fragment = snippet.fragments.min { $0.position < $1.position }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let fragment {
                    LanguageIconView(fragment.language, size: 12)
                    Text(fragment.fileName.isEmpty ? LanguageName.display(fragment.language) : fragment.fileName)
                        .lineLimit(1)
                }
                if snippet.fragments.count > 1 {
                    Text("+\(snippet.fragments.count - 1) more").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(isOn: Binding(get: { settings.wrapLines }, set: { settings.wrapLines = $0 })) {
                    Label("Wrap", symbol: .wrapLines)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .touchTarget()
                .help("Wrap long lines")
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            ScrollView(.vertical) {
                CodeView(code: fragment?.code ?? "", language: fragment?.language ?? "plaintext")
                    .padding(.horizontal, 6)
                    .id(snippet.id)
            }
            .frame(height: 150)
        }
    }

    private func choose(option: Bool, command: Bool = false) {
        guard !lock.isLocked, let snippet = model.highlightedSnippet else { return }
        switch QuickSearchAction.forReturn(option: option, command: command, settings: settings) {
        case .copy:
            model.copy(snippet)
            onClose()
        case .paste:
            model.list.recordCopy(snippet)
            // Close first, so the previous app comes back to the front before the paste.
            onClose()
            ActiveAppPaster.shared.paste(QuickSearchModel.code(of: snippet))
        case .open:
            open(snippet)
        }
    }

    private func open(_ snippet: Snippet) {
        onClose()
        NSWorkspace.shared.open(DeepLink.snippet(snippet.id).url)
    }
}
#endif
