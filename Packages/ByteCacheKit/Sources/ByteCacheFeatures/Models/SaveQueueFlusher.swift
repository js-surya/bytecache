import ByteCacheCore
import Foundation
import Network
import Observation

/// Uploads saves that were queued while offline: on launch, when the app comes back to the
/// foreground and when the network returns. Keeps queue order; stops at the first offline error.
@MainActor @Observable
public final class SaveQueueFlusher {
    /// Saves waiting for the current account's server.
    public private(set) var pendingCount = 0
    public private(set) var isFlushing = false
    /// Bumped after uploads so lists can reload.
    public private(set) var uploadedGeneration = 0

    @ObservationIgnored private let session: SessionManager
    @ObservationIgnored private let queue: PendingSaveQueue
    @ObservationIgnored private var monitor: NWPathMonitor?

    public init(session: SessionManager, queue: PendingSaveQueue = .shared) {
        self.session = session
        self.queue = queue
        refresh()
    }

    public func refresh() {
        pendingCount = session.client.map { queue.items(for: $0.server).count } ?? 0
    }

    /// Returns how many snippets were uploaded.
    @discardableResult
    public func flush() async -> Int {
        guard !isFlushing, let client = session.client else { refresh(); return 0 }
        isFlushing = true
        defer { isFlushing = false; refresh() }
        var uploaded = 0
        for item in queue.items(for: client.server) {
            do {
                _ = try await client.create(item.draft)
                try? queue.remove(item.id)
                uploaded += 1
            } catch .offline {
                break
            } catch .unauthorized {
                session.handleUnauthorized()
                break
            } catch {
                // Rejected by the server: keep it so nothing is lost; the user can discard it.
                continue
            }
        }
        if uploaded > 0 { uploadedGeneration += 1 }
        return uploaded
    }

    /// Drops every queued save for the current server.
    public func discardAll() {
        guard let server = session.client?.server else { return }
        for item in queue.items(for: server) { try? queue.remove(item.id) }
        refresh()
    }

    /// Flushes whenever the network comes back.
    public func startMonitoring() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.flush() }
        }
        monitor.start(queue: DispatchQueue(label: "ByteCache.SaveQueue"))
        self.monitor = monitor
    }
}
