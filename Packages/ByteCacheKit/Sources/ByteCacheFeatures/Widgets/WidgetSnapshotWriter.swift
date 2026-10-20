import ByteCacheCore
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Keeps the widgets' snapshot up to date: pinned and recent snippets of the active server, plus
/// the lists a configurable widget can show (favorites, Smart Groups, tags, languages).
@MainActor
public final class WidgetSnapshotWriter {
    public static let rowsPerList = 10
    /// Snippets per list for the configurable widget, with shorter code, so the snapshot stays small.
    static let rowsPerExtraList = 8
    static let extraListCodeLimit = 4_000
    /// Most snippets loaded for the configurable widget's lists.
    static let libraryLimit = 1_000

    private let session: SessionManager
    private let store: WidgetSnapshotStore
    private let smartGroups: () -> [SmartGroup]
    private let reload: () -> Void
    /// The whole library, reused for a minute so quick successive refreshes don't refetch it.
    private var library: (server: ServerURL, snippets: [Snippet], loaded: Date)?

    public init(session: SessionManager, store: WidgetSnapshotStore = WidgetSnapshotStore(),
                smartGroups: @escaping () -> [SmartGroup] = { [] },
                reload: @escaping () -> Void = WidgetSnapshotWriter.reloadAllWidgets) {
        self.session = session
        self.store = store
        self.smartGroups = smartGroups
        self.reload = reload
    }

    public nonisolated static func reloadAllWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    public func refresh() async {
        guard let client = session.client else {
            try? store.clear()
            reload()
            return
        }
        let name = client.server.base.host() ?? client.server.base.absoluteString
        do {
            let pinned = try await client.snippets(SnippetQuery(pinned: true, limit: Self.rowsPerList)).snippets
            let recent = try await client.snippets(SnippetQuery(limit: Self.rowsPerList)).snippets
            let all = try await allSnippets(client)
            let (sources, lists) = Self.extraLists(library: all, smartGroups: smartGroups())
            try store.write(WidgetSnapshot(serverName: name, pinned: pinned.map(WidgetSnippet.init),
                                           recent: recent.map(WidgetSnippet.init), sources: sources, lists: lists))
            reload()
        } catch {
            // Offline or server trouble: widgets keep the last snapshot of this server. With none,
            // they say so instead of asking to sign in.
            if let last = store.read(), last.serverName == name, last.problem == nil { return }
            try? store.write(WidgetSnapshot(serverName: name, pinned: [], recent: [], problem: "Can't reach \(name)"))
            reload()
        }
    }

    /// Every snippet (not in the Recycle Bin), at most `libraryLimit`; reused for a minute.
    private func allSnippets(_ client: APIClient) async throws(APIError) -> [Snippet] {
        if let library, library.server == client.server, Date().timeIntervalSince(library.loaded) < 60 {
            return library.snippets
        }
        var all: [Snippet] = []
        var query = SnippetQuery(limit: 100)
        repeat {
            query.offset = all.count
            let page = try await client.snippets(query)
            all += page.snippets
            if !page.hasMore || page.snippets.isEmpty { break }
        } while all.count < Self.libraryLimit
        library = (client.server, all, Date())
        return all
    }

    /// What a configurable widget can show, and its snippets: favorites, each Smart Group, tag and
    /// language in the library. Newest first.
    static func extraLists(library: [Snippet], smartGroups: [SmartGroup]) -> ([WidgetSource], [String: [WidgetSnippet]]) {
        var sources: [WidgetSource] = [.recent, .pinned, .favorites]
        var lists: [String: [WidgetSnippet]] = [:]
        let newest = library.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        func add(_ source: WidgetSource, _ matches: (Snippet) -> Bool) {
            if !sources.contains(source) { sources.append(source) }
            lists[source.id] = newest.filter(matches).prefix(rowsPerExtraList)
                .map { WidgetSnippet($0).capped(extraListCodeLimit) }
        }
        add(.favorites) { $0.isFavorite }
        for group in smartGroups {
            add(WidgetSource(kind: .smartGroup, value: group.id.uuidString, title: group.name)) { group.matches($0) }
        }
        let tags = Set(library.flatMap { $0.categories.map { $0.lowercased() } }).sorted()
        for tag in tags {
            add(WidgetSource(kind: .tag, value: tag, title: "#\(tag)")) { $0.categories.contains { $0.lowercased() == tag } }
        }
        let languages = Set(library.flatMap { $0.fragments.map(\.language) }).sorted()
        for language in languages {
            add(WidgetSource(kind: .language, value: language, title: LanguageName.display(language))) { snippet in
                snippet.fragments.contains { $0.language == language }
            }
        }
        return (sources, lists)
    }
}
