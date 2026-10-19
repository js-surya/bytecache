import ByteCatchCore
import Foundation

/// ByteCatch's JSON backup (importable again) plus the ZIP-of-files export.
public struct SnippetBackup: Codable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public struct File: Codable, Equatable, Sendable {
            public var fileName, code, language: String
            public init(fileName: String, code: String, language: String) {
                self.fileName = fileName
                self.code = code
                self.language = language
            }
        }

        public var title, description: String
        public var categories: [String]
        public var isPublic, isPinned, isFavorite: Bool
        public var fragments: [File]

        public init(title: String, description: String, categories: [String], isPublic: Bool, isPinned: Bool,
                    isFavorite: Bool, fragments: [File]) {
            self.title = title
            self.description = description
            self.categories = categories
            self.isPublic = isPublic
            self.isPinned = isPinned
            self.isFavorite = isFavorite
            self.fragments = fragments
        }

        init(_ s: Snippet) {
            self.init(title: s.title, description: s.description, categories: s.categories, isPublic: s.isPublic,
                      isPinned: s.isPinned, isFavorite: s.isFavorite,
                      fragments: s.fragments.sorted { $0.position < $1.position }
                        .map { File(fileName: $0.fileName, code: $0.code, language: $0.language) })
        }

        var draft: SnippetDraft {
            SnippetDraft(title: title, description: description, categories: categories,
                         fragments: fragments.map { FragmentDraft(fileName: $0.fileName, code: $0.code, language: $0.language) },
                         isPublic: isPublic)
        }

        var matchKey: String { title.lowercased() + "\u{0}" + (fragments.first?.code ?? "") }
    }

    public struct InvalidBackup: Error {}

    public var format = "bytecatch-backup"
    public var version = 1
    public var exportedAt = Date()
    public var server: String
    public var snippets: [Item]

    public init(snippets: [Snippet], server: String) {
        self.server = server
        self.snippets = snippets.map(Item.init)
    }

    public func with(_ items: [Item]) -> SnippetBackup {
        var copy = self
        copy.snippets = items
        return copy
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SnippetBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(SnippetBackup.self, from: data)
        guard backup.format == "bytecatch-backup" else { throw InvalidBackup() }
        return backup
    }

    /// Every snippet as it would be saved one by one: `<title>.<ext>` or a `<title>/` folder; names made unique.
    public static func folder(for snippets: [Snippet]) -> FileWrapper {
        var children: [String: FileWrapper] = [:]
        for snippet in snippets {
            let wrapper = SnippetExport.fileWrapper(for: snippet)
            let preferred = wrapper.preferredFilename ?? "snippet"
            let stem = (preferred as NSString).deletingPathExtension, ext = (preferred as NSString).pathExtension
            var name = preferred, counter = 2
            while children[name] != nil {
                name = wrapper.isDirectory || ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
                counter += 1
            }
            wrapper.preferredFilename = name
            children[name] = wrapper
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    /// Zips a folder with the system's own archiver (`NSFileCoordinator .forUploading`). Returns a temporary file.
    public static func zip(folder: FileWrapper, named name: String) throws -> URL {
        let work = FileManager.default.temporaryDirectory.appending(path: "bytecatch-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let source = work.appending(path: name)
        try folder.write(to: source, options: .atomic, originalContentsURL: nil)
        let destination = work.appending(path: "\(name).zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .forUploading, error: &coordinationError) { zipped in
            do { try FileManager.default.copyItem(at: zipped, to: destination) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return destination
    }
}

/// Reads every snippet of the account (all pages).
@MainActor
enum SnippetFetcher {
    static func all(_ client: APIClient) async throws(APIError) -> [Snippet] {
        var result: [Snippet] = []
        var query = SnippetQuery(limit: 100)
        while true {
            let page = try await client.snippets(query)
            result += page.snippets
            guard page.hasMore, !page.snippets.isEmpty else { return result }
            query.offset = result.count
        }
    }
}

/// Recreates snippets from a backup, skipping ones already on the server (same title and code).
@MainActor
public struct BackupImporter {
    public struct Result: Equatable { public var created = 0, skipped = 0, failed = 0 }
    let session: SessionManager

    public init(session: SessionManager) {
        self.session = session
    }

    public func importBackup(_ backup: SnippetBackup) async throws(APIError) -> Result {
        guard let client = session.client else { throw .unauthorized }
        let existing = Set(try await SnippetFetcher.all(client).map { SnippetBackup.Item($0).matchKey })
        var result = Result()
        for item in backup.snippets {
            if existing.contains(item.matchKey) {
                result.skipped += 1
                continue
            }
            do {
                let created = try await client.create(item.draft)
                if item.isPinned { try? await client.setPinned(id: created.id, true) }
                if item.isFavorite { try? await client.setFavorite(id: created.id, true) }
                result.created += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }
}
