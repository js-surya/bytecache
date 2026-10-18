import ByteCatchCore
import Foundation
import Observation

/// The middle column: one page-at-a-time list for the current sidebar selection and search.
@MainActor @Observable
public final class SnippetListModel {
    public var selection: SidebarItem = .all
    public var searchText = ""
    public var searchCode = false
    public var sort: SnippetSort = .newest

    public private(set) var snippets: [Snippet] = []
    public private(set) var isOffline = false
    public private(set) var isLoading = false
    public var error: String?

    @ObservationIgnored private(set) var pendingSearch: Task<Void, Never>?
    @ObservationIgnored private var hasMore = false
    @ObservationIgnored private var loadingMore = false
    @ObservationIgnored private var generation = 0

    private let session: SessionManager
    private let cache: SnippetCache?
    private let searchDelay: Duration

    public init(session: SessionManager, cache: SnippetCache?, searchDelay: Duration = .milliseconds(300)) {
        self.session = session
        self.cache = cache
        self.searchDelay = searchDelay
    }

    var query: SnippetQuery {
        var q = SnippetQuery()
        let search = searchText.trimmingCharacters(in: .whitespaces)
        q.search = search.isEmpty ? nil : search
        q.searchCode = searchCode
        q.sort = sort
        switch selection {
        case .all: break
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
        generation += 1
        let current = generation
        let q = query
        guard let client = session.client else { return }
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let page = try await client.snippets(q)
            guard current == generation else { return }
            snippets = page.snippets
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
            let page = try await client.snippets(q)
            guard started == generation else { return }
            let known = Set(snippets.map(\.id))
            snippets += page.snippets.filter { !known.contains($0.id) }
            hasMore = page.hasMore
            cache?.store(page.snippets, server: client.server)
        } catch {
            handle(error, offlineQuery: nil, server: client.server)
        }
    }

    // MARK: Row actions

    public func togglePin(_ snippet: Snippet) async {
        await mutate(snippet, change: { $0.isPinned.toggle() }) { client, s throws(APIError) in
            try await client.setPinned(id: s.id, s.isPinned)
        }
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
        if let server = session.client?.server { cache?.upsert(snippet, server: server) }
    }

    // MARK: Private

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
