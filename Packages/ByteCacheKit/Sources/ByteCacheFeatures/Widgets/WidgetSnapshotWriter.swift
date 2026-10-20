import ByteCacheCore
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Keeps the widgets' snapshot (pinned + recent snippets of the active server) up to date.
@MainActor
public final class WidgetSnapshotWriter {
    public static let rowsPerList = 10

    private let session: SessionManager
    private let store: WidgetSnapshotStore
    private let reload: () -> Void

    public init(session: SessionManager, store: WidgetSnapshotStore = WidgetSnapshotStore(),
                reload: @escaping () -> Void = WidgetSnapshotWriter.reloadAllWidgets) {
        self.session = session
        self.store = store
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
            try store.write(WidgetSnapshot(serverName: name, pinned: pinned.map(WidgetSnippet.init),
                                           recent: recent.map(WidgetSnippet.init)))
            reload()
        } catch {
            // Offline or server trouble: widgets keep the last snapshot of this server. With none,
            // they say so instead of asking to sign in.
            if let last = store.read(), last.serverName == name, last.problem == nil { return }
            try? store.write(WidgetSnapshot(serverName: name, pinned: [], recent: [], problem: "Can't reach \(name)"))
            reload()
        }
    }
}
