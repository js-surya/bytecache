import ByteCacheCore
import ByteCacheLanguage
import Foundation

public enum IntentFailure: Error, Equatable {
    case signedOut, emptyText
    /// Offline: kept on the device and uploaded later.
    case queued
    case api(APIError)

    public var message: String {
        switch self {
        case .signedOut: "Open ByteCache and sign in first."
        case .emptyText: "There's no code to save."
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

    private static func client(store: any CredentialStore, transport: any HTTPTransport) -> APIClient? {
        store.load()?.makeClient(transport: transport)
    }

    private static func forgetToken(in store: any CredentialStore) {
        guard let credentials = store.load() else { return }
        try? store.save(credentials.signedOut)
    }
}
