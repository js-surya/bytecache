import Foundation

/// A new snippet that couldn't be uploaded because the device was offline.
public struct PendingSave: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let server: ServerURL
    public let draft: SnippetDraft
    public let createdAt: Date
}

/// Saves waiting for the network, kept as JSON in the App Group container so the app, the share
/// extensions and App Intents all add to (and the app drains) the same queue.
/// Reads the file every time: another process may have changed it.
public struct PendingSaveQueue: Sendable {
    public let directory: URL
    private var file: URL { directory.appending(path: "pending-saves.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// The queue shared by the app and its extensions.
    public static var shared: PendingSaveQueue {
        let container = AppEnvironment.appGroupID
            .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? URL.applicationSupportDirectory
        return PendingSaveQueue(directory: container.appending(path: "PendingSaves"))
    }

    public var all: [PendingSave] { (try? coordinatedRead()) ?? [] }
    public var count: Int { all.count }

    public func items(for server: ServerURL) -> [PendingSave] {
        all.filter { $0.server == server }
    }

    public func enqueue(_ draft: SnippetDraft, server: ServerURL) throws {
        try update { $0.append(PendingSave(id: UUID(), server: server, draft: draft, createdAt: .now)) }
    }

    public func remove(_ id: UUID) throws {
        try update { $0.removeAll { $0.id == id } }
    }

    // MARK: Private

    private func update(_ change: (inout [PendingSave]) -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var failure: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: [], error: &coordinationError) { url in
            do {
                var items = try Self.decode(url)
                change(&items)
                try JSONEncoder().encode(items).write(to: url, options: .atomic)
            } catch {
                failure = error
            }
        }
        if let error = coordinationError ?? failure { throw error }
    }

    private func coordinatedRead() throws -> [PendingSave] {
        var result: Result<[PendingSave], any Error> = .success([])
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
            result = Result { try Self.decode(url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private static func decode(_ url: URL) throws -> [PendingSave] {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return try JSONDecoder().decode([PendingSave].self, from: Data(contentsOf: url))
    }
}
