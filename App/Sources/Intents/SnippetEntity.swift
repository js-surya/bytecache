import AppIntents
import ByteCatchCore
import ByteCatchFeatures

struct SnippetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Snippet"
    static let defaultQuery = SnippetEntityQuery()

    let id: Int
    let title: String
    let language: String
    let code: String

    init(_ snippet: Snippet) {
        id = snippet.id
        title = snippet.title
        let first = snippet.fragments.sorted { $0.position < $1.position }.first
        language = first.map { LanguageName.display($0.language) } ?? ""
        code = first?.code ?? ""
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
