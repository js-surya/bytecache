import Foundation
import SwiftData

/// One cached snippet. The full snippet is kept as JSON; the filter fields are copied out for querying.
@Model
final class CachedSnippet {
    @Attribute(.unique) var key: String
    var serverKey: String
    var id: Int
    var payload: Data
    var updatedAt: Date?
    var isPinned: Bool
    var isFavorite: Bool
    var isRecycled: Bool

    init(serverKey: String, snippet: Snippet, payload: Data) {
        self.key = CachedSnippet.key(serverKey, snippet.id)
        self.serverKey = serverKey
        self.id = snippet.id
        self.payload = payload
        self.updatedAt = snippet.updatedAt
        self.isPinned = snippet.isPinned
        self.isFavorite = snippet.isFavorite
        self.isRecycled = snippet.expiryDate != nil
    }

    static func key(_ serverKey: String, _ id: Int) -> String { "\(serverKey)#\(id)" }
}

/// Recently fetched snippets, so the list and details work offline. Writes still need the network.
@MainActor
public final class SnippetCache {
    public static let maxPerServer = 500

    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// On disk the store lives in the App Group container so the share extension and intents can read it.
    public init(inMemory: Bool = false) throws {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(url: Self.storeURL())
        }
        let container = try ModelContainer(for: CachedSnippet.self, configurations: configuration)
        context = ModelContext(container)
    }

    /// Saves a page of snippets. One lookup for the whole page, and unchanged snippets aren't rewritten
    /// (a list refresh mostly brings back what's already cached).
    public func store(_ snippets: [Snippet], server: ServerURL) {
        let serverKey = server.cacheKey
        let keys = snippets.map { CachedSnippet.key(serverKey, $0.id) }
        let existing = Dictionary(((try? context.fetch(FetchDescriptor(predicate: #Predicate<CachedSnippet> { keys.contains($0.key) }))) ?? [])
            .map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for snippet in snippets {
            guard let payload = try? encoder.encode(snippet) else { continue }
            if let record = existing[CachedSnippet.key(serverKey, snippet.id)] {
                if record.payload == payload { continue }
                context.delete(record)
            }
            context.insert(CachedSnippet(serverKey: serverKey, snippet: snippet, payload: payload))
            changed = true
        }
        guard changed else { return }
        trim(server: server)
        save()
    }

    public func upsert(_ snippet: Snippet, server: ServerURL) {
        write(snippet, server: server)
        trim(server: server)
        save()
    }

    public func remove(id: Int, server: ServerURL) {
        if let existing = record(id: id, server: server) {
            context.delete(existing)
            save()
        }
    }

    /// Cached snippets matching the query's filters. Paging is ignored: everything cached is local already.
    public func all(server: ServerURL, matching query: SnippetQuery) -> [Snippet] {
        let serverKey = server.cacheKey
        let recycled = query.recycled
        var predicate = #Predicate<CachedSnippet> { $0.serverKey == serverKey && $0.isRecycled == recycled }
        if query.pinned {
            predicate = #Predicate<CachedSnippet> { $0.serverKey == serverKey && $0.isRecycled == recycled && $0.isPinned }
        } else if query.favorites {
            predicate = #Predicate<CachedSnippet> { $0.serverKey == serverKey && $0.isRecycled == recycled && $0.isFavorite }
        }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let snippets = ((try? context.fetch(descriptor)) ?? []).compactMap(decode)
        return SnippetOrdering.arranged(snippets.filter { matches($0, query) }, by: query.sort)
    }

    public func snippet(id: Int, server: ServerURL) -> Snippet? {
        record(id: id, server: server).flatMap(decode)
    }

    // MARK: Private

    private func write(_ snippet: Snippet, server: ServerURL) {
        guard let payload = try? encoder.encode(snippet) else { return }
        if let existing = record(id: snippet.id, server: server) {
            context.delete(existing)
        }
        context.insert(CachedSnippet(serverKey: server.cacheKey, snippet: snippet, payload: payload))
    }

    private func trim(server: ServerURL) {
        let serverKey = server.cacheKey
        // Counting is cheap; loading and sorting every row is only worth it when there are too many.
        let count = (try? context.fetchCount(FetchDescriptor(predicate: #Predicate<CachedSnippet> { $0.serverKey == serverKey }))) ?? 0
        guard count > Self.maxPerServer else { return }
        let descriptor = FetchDescriptor(
            predicate: #Predicate<CachedSnippet> { $0.serverKey == serverKey },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        // Not `fetchOffset`: SwiftData ignores it for unsaved inserts and would return every row.
        for stale in ((try? context.fetch(descriptor)) ?? []).dropFirst(Self.maxPerServer) {
            context.delete(stale)
        }
    }

    private func record(id: Int, server: ServerURL) -> CachedSnippet? {
        let key = CachedSnippet.key(server.cacheKey, id)
        var descriptor = FetchDescriptor(predicate: #Predicate<CachedSnippet> { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func decode(_ record: CachedSnippet) -> Snippet? {
        try? decoder.decode(Snippet.self, from: record.payload)
    }

    private func matches(_ snippet: Snippet, _ query: SnippetQuery) -> Bool {
        if let language = query.language, !language.isEmpty,
           !snippet.fragments.contains(where: { $0.language == language }) {
            return false
        }
        if !query.categories.isEmpty {
            let wanted = Set(query.categories.map { $0.lowercased() })
            if wanted.isDisjoint(with: snippet.categories.map { $0.lowercased() }) { return false }
        }
        if let search = query.search?.trimmingCharacters(in: .whitespaces), !search.isEmpty {
            let inText = snippet.title.localizedCaseInsensitiveContains(search)
                || snippet.description.localizedCaseInsensitiveContains(search)
            let inCode = query.searchCode
                && snippet.fragments.contains { $0.code.localizedCaseInsensitiveContains(search) }
            if !inText && !inCode { return false }
        }
        return true
    }

    private func save() {
        try? context.save()
    }

    private static func storeURL() -> URL {
        let directory = AppEnvironment.appGroupID
            .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "SnippetCache.store")
    }
}
