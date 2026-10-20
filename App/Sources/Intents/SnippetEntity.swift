import AppIntents
import ByteCacheCore
import ByteCacheFeatures

struct SnippetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Snippet"
    static let defaultQuery = SnippetEntityQuery()

    let id: Int
    // Properties a shortcut can pick from each result (e.g. "Code" of a found snippet).
    @Property(title: "Title") var title: String
    @Property(title: "Language") var language: String
    @Property(title: "Code") var code: String
    @Property(title: "Tags") var tags: [String]

    init(_ snippet: Snippet) {
        id = snippet.id
        let files = snippet.fragments.sorted { $0.position < $1.position }
        title = snippet.title.isEmpty ? "Untitled snippet" : snippet.title
        language = files.first.map { LanguageName.display($0.language) } ?? ""
        // With App Lock on, shortcuts get titles only, not code.
        code = AppEnvironment.isAppLockEnabled ? "" : files.map(\.code).joined(separator: "\n\n")
        tags = snippet.categories
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(language)")
    }
}

struct SnippetEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [Int]) async throws -> [SnippetEntity] {
        guard let server = AppEnvironment.makeCredentialStore().load()?.server, let cache = try? SnippetCache() else { return [] }
        return identifiers.compactMap { cache.snippet(id: $0, server: server) }.map(SnippetEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SnippetEntity] {
        await IntentActions.search(string, store: AppEnvironment.makeCredentialStore(), cache: try? SnippetCache())
            .map(SnippetEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SnippetEntity] {
        guard let server = AppEnvironment.makeCredentialStore().load()?.server, let cache = try? SnippetCache() else { return [] }
        return cache.all(server: server, matching: SnippetQuery()).prefix(20).map(SnippetEntity.init)
    }
}
