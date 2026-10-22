import ByteCacheCore
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
    /// Nothing matched exactly, so `snippets` holds close (fuzzy) title matches from the cache.
    public private(set) var showsCloseMatches = false
    /// Languages and tags in the library, for search suggestions. Set by the view that owns the sidebar.
    public var knownLanguages: [String] = []
    public var knownCategories: [String] = []
    /// Smart Group definitions (from `AppSettings`). Set by the view that owns the sidebar.
    public var smartGroups: [SmartGroup] = []

    /// The list's title: the selected sidebar item, or the Smart Group's name.
    public var title: String {
        if case .smartGroup(let id) = selection { return smartGroups.first { $0.id == id }?.name ?? "Smart Group" }
        return selection.title
    }
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
    @ObservationIgnored nonisolated(unsafe) private var changeObserver: NSObjectProtocol?

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
        // Other lists (each iPhone tab has its own) say when they change a snippet.
        changeObserver = NotificationCenter.default.addObserver(forName: SnippetChange.notification, object: nil, queue: nil) {
            [weak self] note in
            guard let change = note.userInfo?[SnippetChange.key] as? SnippetChange,
                  let self, note.object as AnyObject? !== self else { return }
            MainActor.assumeIsolated { self.apply(change) }
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
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
            announce(.updated(saved), server: client.server)
        } catch {
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    /// Renames a snippet (Suggest Title). Sends the whole snippet (PUT replaces everything).
    public func rename(_ snippet: Snippet, to raw: String) async {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let client = session.client else { return }
        // Opened by id, a snippet may not be on the loaded page.
        let index = snippets.firstIndex(where: { $0.id == snippet.id })
        let original = index.map { snippets[$0] } ?? snippet
        var draft = SnippetDraft(from: original)
        draft.title = title
        if let index { snippets[index].title = title }
        do {
            let saved = try await client.update(id: snippet.id, draft)
            if let i = snippets.firstIndex(where: { $0.id == snippet.id }) { snippets[i] = saved }
            cache?.upsert(saved, server: client.server)
            announce(.updated(saved), server: client.server)
        } catch {
            if let i = snippets.firstIndex(where: { $0.id == snippet.id }) { snippets[i] = original }
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
            announce(.updated(saved), server: client.server)
        } catch {
            if let i = snippets.firstIndex(where: { $0.id == snippet.id }) { snippets[i] = original }
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    /// Counts a copy towards Most Used.
    public func recordCopy(_ snippet: Snippet) {
        AppLog.shared.record("snippet", "copied a snippet (\(snippet.fragments.count) file\(snippet.fragments.count == 1 ? "" : "s"))")
        guard let server = session.client?.server else { return }
        usage.recordCopy(snippetID: snippet.id, server: server)
    }

    /// The search field split into text and filters (`lang:`, `#tag`, `is:pinned`, `is:favorite`).
    var parsedSearch: SearchSyntax { SearchSyntax.parse(searchText) }

    /// Suggestions for what's being typed in the search field.
    public var searchSuggestions: [SearchSuggestion] {
        SearchSyntax.suggestions(for: searchText, languages: knownLanguages, categories: knownCategories,
                                 languageName: LanguageName.display)
    }

    var query: SnippetQuery {
        var q = SnippetQuery()
        let parsed = parsedSearch
        q.search = parsed.text.isEmpty ? nil : parsed.text
        q.searchCode = searchCode
        q.sort = sort
        switch selection {
        case .all, .mostUsed, .publicSnippets, .smartGroup: break
        case .pinned: q.pinned = true
        case .favorites: q.favorites = true
        case .recycleBin: q.recycled = true
        case .language(let id): q.language = id
        case .category(let name): q.categories = [name.lowercased()]
        }
        // Typed filters narrow the selection further (a selected language wins over `lang:`).
        if q.language == nil, let language = parsed.language {
            q.language = knownLanguages.first { $0.lowercased() == language } ?? language
        }
        for category in parsed.categories where !q.categories.contains(category) { q.categories.append(category) }
        if parsed.pinned { q.pinned = true }
        if parsed.favorite { q.favorites = true }
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
        showsCloseMatches = false
        guard let client = session.client else { return }
        isLoading = true
        defer { if current == generation { isLoading = false } }
        if selection == .mostUsed {
            await loadMostUsed(client: client, generation: current)
            return
        }
        if case .smartGroup(let id) = selection {
            await loadSmartGroup(id, query: q, client: client, generation: current)
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
            showsCloseMatches = false
            if page.snippets.isEmpty, let text = q.search, selection != .publicSnippets {
                // Nothing matched exactly: offer titles that nearly match, from this device's cache.
                var base = q
                base.search = nil
                let close = SearchRanking.closeMatches(cache?.all(server: client.server, matching: base) ?? [], to: text)
                snippets = close
                showsCloseMatches = !close.isEmpty
            }
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
            // The cache keeps the newest few hundred; pages past that would only be trimmed again.
            if q.offset < SnippetCache.maxPerServer { cache?.store(page.snippets, server: client.server) }
        } catch {
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    // MARK: Row actions

    /// Pinned snippets are shown first (as the server sorts them), so pinning moves a snippet.
    public func togglePin(_ snippet: Snippet) async {
        guard let client = session.client, let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let before = snippets
        let original = snippets[index]
        snippets[index].isPinned.toggle()
        let updated = snippets[index]
        show(updated, server: client.server)
        do {
            try await client.setPinned(id: updated.id, updated.isPinned)
            cache?.upsert(updated, server: client.server)
        } catch {
            snippets = before
            announce(.updated(original), server: client.server)
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

    /// Moves an expired snippet to the Recycle Bin. True when it's done (or the snippet is already gone).
    public func recycleExpired(id: Int) async -> Bool {
        guard let client = session.client else { return false }
        if let snippet = snippets.first(where: { $0.id == id }) {
            snippets.removeAll { $0.id == id }
            do {
                try await client.recycle(id: id)
            } catch .notFound {
                return true
            } catch {
                snippets = arranged(snippets + [snippet])
                return false
            }
        } else {
            do {
                try await client.recycle(id: id)
            } catch .notFound {
                return true
            } catch {
                return false
            }
        }
        if let fresh = try? await client.snippet(id: id) { cache?.upsert(fresh, server: client.server) }
        announce(.recycled(id), server: client.server)
        return true
    }

    public func recycle(_ snippet: Snippet) async {
        await removeRow(snippet, then: .recycled(snippet.id)) { client throws(APIError) in try await client.recycle(id: snippet.id) }
    }

    public func restore(_ snippet: Snippet) async {
        await removeRow(snippet, then: .restored(snippet.id)) { client throws(APIError) in try await client.restore(id: snippet.id) }
    }

    public func deletePermanently(_ snippet: Snippet) async {
        await removeRow(snippet, uncache: true, then: .deleted(snippet.id)) { client throws(APIError) in try await client.delete(id: snippet.id) }
    }

    /// Puts a saved or edited snippet into the list without a refetch.
    public func didSave(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else if selection == .all {
            snippets.insert(snippet, at: 0)
        }
        snippets = arranged(snippets)
        if let server = session.client?.server {
            cache?.upsert(snippet, server: server)
            announce(.updated(snippet), server: server)
        }
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

    /// Most Used keeps its own order (by copy count). While searching, best matches come first.
    private func arranged(_ list: [Snippet]) -> [Snippet] {
        guard selection != .mostUsed else { return list }
        let sorted = SnippetOrdering.arranged(list, by: sort)
        let text = parsedSearch.text
        return text.isEmpty ? sorted : SearchRanking.arranged(sorted, by: text)
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
        let search = parsedSearch.text
        snippets = search.isEmpty ? loaded : loaded.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search)
        }
        hasMore = false
        error = nil
    }

    /// Smart Groups are filtered on the device: every snippet (paged from the server, or the
    /// offline cache) that matches the group's rules and the typed search.
    private func loadSmartGroup(_ id: UUID, query q: SnippetQuery, client: APIClient, generation current: Int) async {
        guard let group = smartGroups.first(where: { $0.id == id }) else {
            snippets = []
            hasMore = false
            return
        }
        var all: [Snippet] = []
        var base = SnippetQuery(sort: sort, limit: 100)
        do {
            repeat {
                base.offset = all.count
                let page = try await client.snippets(base)
                all += page.snippets
                cache?.store(page.snippets, server: client.server)
                if !page.hasMore || page.snippets.isEmpty { break }
            } while all.count < Self.smartGroupLimit
            isOffline = false
        } catch .unauthorized {
            session.handleUnauthorized()
            return
        } catch {
            isOffline = true
            all = cache?.all(server: client.server, matching: SnippetQuery()) ?? []
        }
        guard current == generation else { return }
        snippets = arranged(all.filter { snippet in
            group.matches(snippet) && Self.matches(snippet, q)
        })
        hasMore = false
        error = nil
    }

    /// Most snippets a Smart Group loads from the server.
    static let smartGroupLimit = 2000

    /// The typed search and filters, applied on the device (for Smart Groups).
    private static func matches(_ snippet: Snippet, _ q: SnippetQuery) -> Bool {
        if let language = q.language, !snippet.fragments.contains(where: { $0.language.caseInsensitiveCompare(language) == .orderedSame }) {
            return false
        }
        for tag in q.categories where !snippet.categories.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            return false
        }
        if q.pinned && !snippet.isPinned { return false }
        if q.favorites && !snippet.isFavorite { return false }
        if let text = q.search {
            let inText = snippet.title.localizedCaseInsensitiveContains(text) || snippet.description.localizedCaseInsensitiveContains(text)
            let inCode = q.searchCode && snippet.fragments.contains { $0.code.localizedCaseInsensitiveContains(text) }
            if !inText && !inCode { return false }
        }
        return true
    }

    private func mutate(
        _ snippet: Snippet, change: (inout Snippet) -> Void,
        send: (APIClient, Snippet) async throws(APIError) -> Void
    ) async {
        guard let client = session.client, let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let original = snippets[index]
        var updated = original
        change(&updated)
        show(updated, server: client.server)
        do {
            try await send(client, updated)
            cache?.upsert(updated, server: client.server)
        } catch {
            show(original, server: client.server)
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    private func removeRow(
        _ snippet: Snippet, uncache: Bool = false, then change: SnippetChange.Kind,
        send: (APIClient) async throws(APIError) -> Void
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
            announce(change, server: client.server)
        } catch {
            snippets.insert(removed, at: min(index, snippets.count))
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    // MARK: Keeping the other lists in step (CP-66)

    /// Whether a snippet belongs in this list, when the snippet itself says so; nil for lists the
    /// server decides (tags, languages, Smart Groups, search…), which only update rows they show.
    private func belongs(_ snippet: Snippet) -> Bool? {
        switch selection {
        case .pinned: snippet.isPinned
        case .favorites: snippet.isFavorite
        case .recycleBin: false
        case .all: parsedSearch.text.isEmpty ? true : nil
        default: nil
        }
    }

    /// Puts a changed snippet in this list (or takes it out) and tells the other lists.
    private func show(_ snippet: Snippet, server: ServerURL) {
        place(snippet)
        announce(.updated(snippet), server: server)
    }

    private func place(_ snippet: Snippet) {
        let index = snippets.firstIndex { $0.id == snippet.id }
        switch (index, belongs(snippet)) {
        case (let i?, false): snippets.remove(at: i)
        case (let i?, _): snippets[i] = snippet
        case (nil, true): snippets.append(snippet)
        case (nil, _): return
        }
        snippets = arranged(snippets)
    }

    private func announce(_ kind: SnippetChange.Kind, server: ServerURL) {
        NotificationCenter.default.post(name: SnippetChange.notification, object: self,
                                        userInfo: [SnippetChange.key: SnippetChange(kind: kind, server: server,
                                                                                    session: ObjectIdentifier(session))])
    }

    private func apply(_ change: SnippetChange) {
        // Only lists on the same session (the app's tabs share one; tests and other windows may not).
        guard change.session == ObjectIdentifier(session), change.server == session.client?.server else { return }
        switch change.kind {
        case .updated(let snippet):
            place(snippet)
        case .deleted(let id):
            snippets.removeAll { $0.id == id }
        case .recycled(let id):
            if selection == .recycleBin { Task { await refresh() } } else { snippets.removeAll { $0.id == id } }
        case .restored(let id):
            if selection == .recycleBin { snippets.removeAll { $0.id == id } } else { Task { await refresh() } }
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

/// A change one list made to a snippet, for the other lists (each iPhone tab has its own).
struct SnippetChange: @unchecked Sendable {
    enum Kind {
        case updated(Snippet)
        case recycled(Int)
        case restored(Int)
        case deleted(Int)
    }

    static let notification = Notification.Name("ByteCache.snippetChanged")
    static let key = "change"

    let kind: Kind
    let server: ServerURL
    let session: ObjectIdentifier
}
