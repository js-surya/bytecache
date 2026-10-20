import ByteCacheCore
import ByteCacheLanguage
import Foundation

public enum IntentFailure: Error, Equatable {
    case signedOut, emptyText, locked, notFound
    /// Offline: kept on the device and uploaded later.
    case queued
    case api(APIError)

    public var message: String {
        switch self {
        case .signedOut: "Open ByteCache and sign in first."
        case .emptyText: "There's no code to save."
        case .locked: "ByteCache is locked. Open it to unlock, then run the shortcut again."
        case .notFound: "That snippet isn't on your server or on this device any more."
        case .queued: "You're offline, so ByteCache saved this on your device. It uploads automatically when you're back online."
        case .api(let error): ErrorText.message(for: error)
        }
    }
}

/// Logic behind the App Intents (Shortcuts, Siri, Spotlight). Works from stored credentials,
/// because intents can run without the app's UI.
@MainActor
public enum IntentActions {
    public static func save(
        text: String, title: String?, language: String?, store: any CredentialStore,
        transport: any HTTPTransport = URLSession.shared, detector: LanguageDetector,
        queue: PendingSaveQueue? = nil
    ) async throws(IntentFailure) -> Snippet {
        guard text.contains(where: { !$0.isWhitespace }) else { throw .emptyText }
        guard let client = client(store: store, transport: transport) else { throw .signedOut }
        let model = CaptureModel(text: text, client: client, detector: detector, queue: queue) {
            forgetToken(in: store)
        }
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { model.title = title }
        if let language, LanguageCatalog.ids.contains(language) { model.pickLanguage(language) }
        do {
            return try await model.save()
        } catch .unauthorized {
            throw .signedOut
        } catch {
            throw model.didQueue ? .queued : .api(error)
        }
    }

    public static func search(
        _ term: String, store: any CredentialStore, transport: any HTTPTransport = URLSession.shared,
        cache: SnippetCache?
    ) async -> [Snippet] {
        guard let credentials = store.load() else { return [] }
        let query = SnippetQuery(search: term, limit: 20)
        if let client = client(store: store, transport: transport) {
            do {
                return try await client.snippets(query).snippets
            } catch .unauthorized {
                forgetToken(in: store)
            } catch {
                // Offline or server trouble: fall back to the cache below.
            }
        }
        return cache?.all(server: credentials.server, matching: query) ?? []
    }

    /// Find Snippets: search text (with `lang:`, `#tag`… filters) plus optional language and tag.
    public static func find(
        _ term: String, language: String? = nil, tag: String? = nil, limit: Int = 20,
        store: any CredentialStore, transport: any HTTPTransport = URLSession.shared, cache: SnippetCache?,
        isLocked: Bool = AppEnvironment.isAppLockEnabled
    ) async throws(IntentFailure) -> [Snippet] {
        guard !isLocked else { throw .locked }
        guard let credentials = store.load() else { throw .signedOut }
        let parsed = SearchSyntax.parse(term)
        var query = SnippetQuery(search: parsed.text.isEmpty ? nil : parsed.text, searchCode: true, limit: limit)
        query.language = blank(language).map { $0.lowercased() } ?? parsed.language
        query.categories = ([blank(tag).map { $0.lowercased() }].compactMap { $0 } + parsed.categories)
        query.pinned = parsed.pinned
        query.favorites = parsed.favorite
        if let client = client(store: store, transport: transport) {
            do {
                return try await client.snippets(query).snippets
            } catch .unauthorized {
                forgetToken(in: store)
                throw .signedOut
            } catch {
                // Offline or server trouble: fall back to the cache below.
            }
        }
        return Array((cache?.all(server: credentials.server, matching: query) ?? []).prefix(limit))
    }

    /// Get Snippet Code: the snippet's code, fresh from the server (or the cache when offline).
    public static func code(
        ofSnippet id: Int, allFiles: Bool, store: any CredentialStore,
        transport: any HTTPTransport = URLSession.shared, cache: SnippetCache?,
        isLocked: Bool = AppEnvironment.isAppLockEnabled
    ) async throws(IntentFailure) -> String {
        guard !isLocked else { throw .locked }
        guard let credentials = store.load() else { throw .signedOut }
        var snippet: Snippet?
        if let client = client(store: store, transport: transport) {
            do {
                snippet = try await client.snippet(id: id)
            } catch .unauthorized {
                forgetToken(in: store)
                throw .signedOut
            } catch {
                // Offline or server trouble: use the cache below.
            }
        }
        guard let snippet = snippet ?? cache?.snippet(id: id, server: credentials.server) else { throw .notFound }
        let files = snippet.fragments.sorted { $0.position < $1.position }
        return allFiles ? files.map(\.code).joined(separator: "\n\n") : files.first?.code ?? ""
    }

    private static func blank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }

    private static func client(store: any CredentialStore, transport: any HTTPTransport) -> APIClient? {
        store.load()?.makeClient(transport: transport)
    }

    private static func forgetToken(in store: any CredentialStore) {
        guard let credentials = store.load() else { return }
        try? store.save(credentials.signedOut)
    }
}
