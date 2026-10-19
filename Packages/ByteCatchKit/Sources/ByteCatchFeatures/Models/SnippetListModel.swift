import ByteCatchCore
import Foundation
import Observation

/// The middle column: one page-at-a-time list for the current sidebar selection and search.
@MainActor @Observable
public final class SnippetListModel {
    public var selection: SidebarItem = .all
    public var searchText = ""
    public var searchCode = false
    /// Remembered between launches when the model has somewhere to store it.
    public var sort: SnippetSort = .newest {
        didSet { sortDefaults?.set(sort.rawValue, forKey: Self.sortKey) }
    }

    public private(set) var snippets: [Snippet] = []
    public private(set) var isOffline = false
    public private(set) var isLoading = false
    public var error: String?
    /// Select mode for bulk actions.
    public var isSelecting = false { didSet { if !isSelecting { selectedIDs = [] } } }
    public var selectedIDs: Set<Int> = []
    public private(set) var isBulkWorking = false

    /// Bumped by the Find command; the list view focuses its search field when it changes.
    public var searchFocusRequest = 0

    @ObservationIgnored private(set) var pendingSearch: Task<Void, Never>?
    @ObservationIgnored private var hasMore = false
    @ObservationIgnored private var loadingMore = false
    @ObservationIgnored private var generation = 0

    let session: SessionManager
    private let cache: SnippetCache?
    private let searchDelay: Duration
    private let usage: UsageTracker
    private let sortDefaults: UserDefaults?
    static let sortKey = "listSort"

    public init(session: SessionManager, cache: SnippetCache?, searchDelay: Duration = .milliseconds(300),
                usage: UsageTracker = UsageTracker(), sortDefaults: UserDefaults? = nil) {
        self.sortDefaults = sortDefaults
        self.session = session
        self.cache = cache
        self.searchDelay = searchDelay
        self.usage = usage
        if let raw = sortDefaults?.string(forKey: Self.sortKey), let saved = SnippetSort(rawValue: raw) { sort = saved }
    }

    /// Public snippets belong to everyone: browse, copy and save only.
    public var isReadOnly: Bool { selection == .publicSnippets }

    private func fetch(_ q: SnippetQuery, _ client: APIClient) async throws(APIError) -> SnippetPage {
        selection == .publicSnippets ? try await client.publicSnippets(q) : try await client.snippets(q)
    }

    // MARK: Bulk actions

    private var selectedSnippets: [Snippet] { snippets.filter { selectedIDs.contains($0.id) } }

    private func bulk(_ work: () async -> Void) async {
        isBulkWorking = true
        await work()
        isBulkWorking = false
        isSelecting = false
    }

    public func bulkSetPinned(_ value: Bool) async {
        await bulk { for s in selectedSnippets where s.isPinned != value { await togglePin(s) } }
    }

    public func bulkSetFavorite(_ value: Bool) async {
        await bulk { for s in selectedSnippets where s.isFavorite != value { await toggleFavorite(s) } }
    }

    public func bulkRecycle() async {
        await bulk { for s in selectedSnippets { await recycle(s) } }
    }

    public func bulkRestore() async {
        await bulk { for s in selectedSnippets { await restore(s) } }
    }

    public func bulkDeleteForever() async {
        await bulk { for s in selectedSnippets { await deletePermanently(s) } }
    }

    public func bulkAddCategory(_ raw: String) async {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        await bulk {
            for s in selectedSnippets where !s.categories.map({ $0.lowercased() }).contains(name) {
                await saveCategories(s, s.categories + [name])
            }
        }
    }

    public func bulkRemoveCategory(_ raw: String) async {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        await bulk {
            for s in selectedSnippets where s.categories.map({ $0.lowercased() }).contains(name) {
                await saveCategories(s, s.categories.filter { $0.lowercased() != name })
            }
        }
    }

    /// Category changes save the whole snippet (PUT replaces everything).
    private func saveCategories(_ snippet: Snippet, _ categories: [String]) async {
        guard let client = session.client else { return }
        var draft = SnippetDraft(from: snippet)
        draft.categories = categories
        do {
            let saved = try await client.update(id: snippet.id, draft)
            if let i = snippets.firstIndex(where: { $0.id == snippet.id }) { snippets[i] = saved }
            cache?.upsert(saved, server: client.server)
        } catch {
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    /// Makes a snippet public or private. Sends the whole snippet (PUT replaces everything).
    public func setPublic(_ snippet: Snippet, _ isPublic: Bool) async {
        guard let client = session.client, let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let original = snippets[index]
        var draft = SnippetDraft(from: original)
        draft.isPublic = isPublic
        snippets[index].isPublic = isPublic
        do {
            let saved = try await client.update(id: snippet.id, draft)
            if let i = snippets.firstIndex(where: { $0.id == snippet.id }) { snippets[i] = saved }
            cache?.upsert(saved, server: client.server)
        } catch {
            if let i = snippets.firstIndex(where: { $0.id == snippet.id }) { snippets[i] = original }
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    /// Counts a copy towards Most Used.
    public func recordCopy(_ snippet: Snippet) {
        guard let server = session.client?.server else { return }
        usage.recordCopy(snippetID: snippet.id, server: server)
    }

    var query: SnippetQuery {
        var q = SnippetQuery()
        let search = searchText.trimmingCharacters(in: .whitespaces)
        q.search = search.isEmpty ? nil : search
        q.searchCode = searchCode
        q.sort = sort
        switch selection {
        case .all, .mostUsed, .publicSnippets: break
        case .pinned: q.pinned = true
        case .favorites: q.favorites = true
        case .recycleBin: q.recycled = true
        case .language(let id): q.language = id
        case .category(let name): q.categories = [name.lowercased()]
        }
        return q
    }

    /// Call from the view whenever `searchText` changes; waits `searchDelay` for typing to settle.
    public func searchTextChanged() {
        pendingSearch?.cancel()
        pendingSearch = Task { [searchDelay] in
            try? await Task.sleep(for: searchDelay)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    public func refresh() async {
        // Another list (an iPhone tab, another window) may have changed the shared choice.
        if let raw = sortDefaults?.string(forKey: Self.sortKey), let saved = SnippetSort(rawValue: raw), saved != sort {
            sort = saved
        }
        generation += 1
        let current = generation
        let q = query
        guard let client = session.client else { return }
        isLoading = true
        defer { if current == generation { isLoading = false } }
        if selection == .mostUsed {
            await loadMostUsed(client: client, generation: current)
            return
        }
        do {
            let page = try await fetch(q, client)
            guard current == generation else { return }
            snippets = arranged(page.snippets)
            hasMore = page.hasMore
            isOffline = false
            error = nil
            cache?.store(page.snippets, server: client.server)
        } catch {
            guard current == generation else { return }
            handle(error, offlineQuery: q, server: client.server)
        }
    }

    public func loadMoreIfNeeded(current snippet: Snippet) async {
        guard hasMore, !loadingMore, !isOffline, snippet.id == snippets.last?.id, let client = session.client else { return }
        loadingMore = true
        defer { loadingMore = false }
        let started = generation
        var q = query
        q.offset = snippets.count
        do {
            let page = try await fetch(q, client)
            guard started == generation else { return }
            let known = Set(snippets.map(\.id))
            snippets = arranged(snippets + page.snippets.filter { !known.contains($0.id) })
            hasMore = page.hasMore
            cache?.store(page.snippets, server: client.server)
        } catch {
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    // MARK: Row actions

    /// Pinned snippets are shown first (as the server sorts them), so pinning moves a snippet.
    public func togglePin(_ snippet: Snippet) async {
        guard let client = session.client, let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let before = snippets
        snippets[index].isPinned.toggle()
        let updated = snippets[index]
        snippets = arranged(snippets)
        do {
            try await client.setPinned(id: updated.id, updated.isPinned)
            cache?.upsert(updated, server: client.server)
        } catch {
            snippets = before
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    /// For a "Pinned" section header; empty inside the Pinned and Recycle Bin lists.
    public var pinnedSection: [Snippet] {
        guard selection != .pinned, selection != .recycleBin else { return [] }
        return snippets.filter(\.isPinned)
    }

    public var otherSection: [Snippet] {
        pinnedSection.isEmpty ? snippets : snippets.filter { !$0.isPinned }
    }

    public func toggleFavorite(_ snippet: Snippet) async {
        await mutate(snippet, change: { $0.isFavorite.toggle() }) { client, s throws(APIError) in
            try await client.setFavorite(id: s.id, s.isFavorite)
        }
    }

    public func recycle(_ snippet: Snippet) async {
        await removeRow(snippet) { client throws(APIError) in try await client.recycle(id: snippet.id) }
    }

    public func restore(_ snippet: Snippet) async {
        await removeRow(snippet) { client throws(APIError) in try await client.restore(id: snippet.id) }
    }

    public func deletePermanently(_ snippet: Snippet) async {
        await removeRow(snippet, uncache: true) { client throws(APIError) in try await client.delete(id: snippet.id) }
    }

    /// Puts a saved or edited snippet into the list without a refetch.
    public func didSave(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else if selection == .all {
            snippets.insert(snippet, at: 0)
        }
        snippets = arranged(snippets)
        if let server = session.client?.server { cache?.upsert(snippet, server: server) }
    }

    /// Makes sure a snippet (from Spotlight or Shortcuts) is in the list; fetches it if needed.
    public func reveal(id: Int) async -> Bool {
        if snippets.contains(where: { $0.id == id }) { return true }
        guard let client = session.client else { return false }
        if let snippet = (try? await client.snippet(id: id)) ?? cache?.snippet(id: id, server: client.server) {
            snippets.insert(snippet, at: 0)
            return true
        }
        return false
    }

    // MARK: Private

    /// Most Used keeps its own order (by copy count).
    private func arranged(_ list: [Snippet]) -> [Snippet] {
        selection == .mostUsed ? list : SnippetOrdering.arranged(list, by: sort)
    }

    /// Most Used comes from this device's copy counts, not a server query.
    private func loadMostUsed(client: APIClient, generation current: Int) async {
        var loaded: [Snippet] = []
        for id in usage.mostUsed(server: client.server, limit: 30) {
            if let snippet = try? await client.snippet(id: id) {
                loaded.append(snippet)
            } else if let cached = cache?.snippet(id: id, server: client.server) {
                loaded.append(cached)
            }
        }
        guard current == generation else { return }
        let search = searchText.trimmingCharacters(in: .whitespaces)
        snippets = search.isEmpty ? loaded : loaded.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search)
        }
        hasMore = false
        error = nil
    }

    private func mutate(
        _ snippet: Snippet, change: (inout Snippet) -> Void,
        send: (APIClient, Snippet) async throws(APIError) -> Void
    ) async {
        guard let client = session.client, let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let original = snippets[index]
        var updated = original
        change(&updated)
        snippets[index] = updated
        do {
            try await send(client, updated)
            cache?.upsert(updated, server: client.server)
        } catch {
            if let i = snippets.firstIndex(where: { $0.id == snippet.id }) { snippets[i] = original }
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    private func removeRow(
        _ snippet: Snippet, uncache: Bool = false, send: (APIClient) async throws(APIError) -> Void
    ) async {
        guard let client = session.client, let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let removed = snippets.remove(at: index)
        do {
            try await send(client)
            if uncache {
                cache?.remove(id: snippet.id, server: client.server)
                usage.forget(snippetID: snippet.id, server: client.server)
            } else if let fresh = try? await client.snippet(id: snippet.id) {
                cache?.upsert(fresh, server: client.server)
            }
        } catch {
            snippets.insert(removed, at: min(index, snippets.count))
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    private func handle(_ error: APIError, offlineQuery: SnippetQuery?, server: ServerURL) {
        switch error {
        case .unauthorized:
            session.handleUnauthorized()
        case .offline where offlineQuery != nil:
            isOffline = true
            self.error = nil
            snippets = cache?.all(server: server, matching: offlineQuery!) ?? []
            hasMore = false
        default:
            self.error = ErrorText.message(for: error)
        }
    }
}
