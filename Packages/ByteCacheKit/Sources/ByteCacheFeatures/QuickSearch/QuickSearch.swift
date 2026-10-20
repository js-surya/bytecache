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

    public func searchChanged() {
        highlighted = 0
        list.searchTextChanged()
    }

    /// Fresh results each time the panel opens.
    public func opened() async {
        highlighted = 0
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
/// The Quick Search window: search field and results. ↑/↓ move, Return copies, ⌘Return opens, Esc closes.
public struct QuickSearchView: View {
    @Bindable var model: QuickSearchModel
    let lock: AppLockModel
    let onClose: () -> Void
    @FocusState private var fieldFocused: Bool
    @Environment(AppSettings.self) private var settings

    public init(model: QuickSearchModel, lock: AppLockModel, onClose: @escaping () -> Void) {
        self.model = model
        self.lock = lock
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
                    .onSubmit { copyHighlighted() }
                    .disabled(lock.isLocked)
            }
            .padding(12)
            Divider()
            content
        }
        .frame(width: 520, height: 380)
        .onChange(of: model.list.searchText) { model.searchChanged() }
        .onKeyPress(.upArrow) { model.move(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.move(by: 1); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command), let snippet = model.highlightedSnippet else { return .ignored }
            open(snippet)
            return .handled
        }
        .task {
            fieldFocused = true
            model.list.searchCode = settings.searchInCode
            if !lock.isLocked { await model.opened() }
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
                            .onTapGesture { model.highlighted = index; copyHighlighted() }
                            .id(snippet.id)
                    }
                }
                .listStyle(.plain)
                .onChange(of: model.highlighted) { _, index in
                    if let id = model.highlightedSnippet?.id { proxy.scrollTo(id) }
                }
            }
            Divider()
            Text("Return copies · ⌘Return opens · Esc closes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }

    private func copyHighlighted() {
        guard !lock.isLocked, let snippet = model.highlightedSnippet else { return }
        model.copy(snippet)
        onClose()
    }

    private func open(_ snippet: Snippet) {
        onClose()
        NSWorkspace.shared.open(DeepLink.snippet(snippet.id).url)
    }
}
#endif
