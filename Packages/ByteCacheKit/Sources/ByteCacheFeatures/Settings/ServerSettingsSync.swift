import ByteCacheCore
import Foundation
import Observation

/// Keeps the settings ByteCache shares with ByteStash's web app in step with the user's preferences on
/// the server (CP-74): Appearance, Show Line Numbers and Search Inside Code. Reads them after signing in
/// and when the app comes back; sends a change straight away, only the keys that changed. Servers older
/// than ByteStash 1.5.13 have no `/api/settings` and are left alone, as are API-key sign-ins (the server
/// keeps settings for a full login only).
@MainActor
public final class ServerSettingsSync {
    private let settings: AppSettings
    private let session: SessionManager
    /// The shared settings as they were after the last sync: what changed here since is what's sent.
    /// (Comparing with the server's values instead would push ByteCache's defaults over keys the user
    /// never set on the web.)
    private var baseline: ServerPreferences?
    private var baselineServer: ServerURL?
    /// Servers that answered without `/api/settings`, for this run of the app.
    private var unsupported: Set<ServerURL> = []
    private var observing = false

    public init(settings: AppSettings, session: SessionManager) {
        self.settings = settings
        self.session = session
    }

    /// The client to use, or nil when this sign-in can't use server settings.
    private var client: APIClient? {
        guard let client = session.client, client.apiKey == nil, client.token != nil,
              !unsupported.contains(client.server) else { return nil }
        return client
    }

    public func pull() async {
        guard let client else { return }
        do {
            let remote = try await client.serverPreferences()
            apply(remote)
            baseline = Self.preferences(from: settings)
            baselineServer = client.server
            observe()
        } catch {
            forget(client.server, after: error)
        }
    }

    /// Sends the shared settings changed here since the last sync.
    public func push() async {
        guard let client, baselineServer == client.server, let baseline else { return }
        let local = Self.preferences(from: settings)
        var changed = ServerPreferences()
        if local.theme != baseline.theme { changed.theme = local.theme }
        if local.showLineNumbers != baseline.showLineNumbers { changed.showLineNumbers = local.showLineNumbers }
        if local.includeCodeInSearch != baseline.includeCodeInSearch { changed.includeCodeInSearch = local.includeCodeInSearch }
        guard !changed.isEmpty else { return }
        self.baseline = local
        do {
            try await client.updateServerPreferences(changed)
        } catch {
            self.baseline = baseline
            forget(client.server, after: error)
        }
    }

    private func apply(_ remote: ServerPreferences) {
        if let theme = remote.theme.flatMap(AppAppearance.init(rawValue:)), theme != settings.appearance {
            settings.appearance = theme
        }
        if let numbers = remote.showLineNumbers, numbers != settings.showLineNumbers { settings.showLineNumbers = numbers }
        if let code = remote.includeCodeInSearch, code != settings.searchInCode { settings.searchInCode = code }
    }

    /// Offline or a lapsed login: try again next time. Anything else means the server has no settings.
    private func forget(_ server: ServerURL, after error: Error) {
        switch error as? APIError {
        case .offline, .unauthorized: break
        default: unsupported.insert(server)
        }
    }

    private func observe() {
        guard !observing else { return }
        observing = true
        withObservationTracking {
            _ = settings.appearance
            _ = settings.showLineNumbers
            _ = settings.searchInCode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observing = false
                await self.push()
                self.observe()
            }
        }
    }

    static func preferences(from settings: AppSettings) -> ServerPreferences {
        ServerPreferences(theme: settings.appearance.rawValue, showLineNumbers: settings.showLineNumbers,
                          includeCodeInSearch: settings.searchInCode)
    }
}
