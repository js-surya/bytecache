import ByteCacheCore
import Foundation
import UniformTypeIdentifiers

/// A file (or text) dropped on ByteCache (CP-92).
public struct DroppedFile: Equatable, Sendable {
    public var name: String?
    public var text: String

    public init(name: String?, text: String) {
        self.name = name
        self.text = text
    }
}

/// Reads what was dropped on the snippet list: code files from Finder, Files or other apps, or text.
/// One file becomes a new snippet; several become one snippet with several files.
public enum DropImport {
    /// What the list accepts.
    public static let types: [UTType] = [.fileURL, .plainText, .data]
    /// More files than this in one drop is more likely a mistake than a snippet.
    public static let maxFiles = 20

    @MainActor
    public static func load(_ providers: [NSItemProvider]) async -> Result<[DroppedFile], ShareProblem> {
        var files: [DroppedFile] = []
        var problem: ShareProblem?
        for provider in providers.prefix(maxFiles) {
            switch await loadOne(provider) {
            case .success(let file):
                files.append(file)
            case .failure(let error):
                let types = provider.registeredTypeIdentifiers.joined(separator: ", ")
                AppLog.shared.record("drop", "couldn't use a dropped item (\(error)); types: \(types)")
                problem = problem ?? error
            }
        }
        if !files.isEmpty { return .success(files) }
        return .failure(problem ?? .noText)
    }

    /// One dropped item, however the dragging app offers it. Finder may describe a CSV as text yet hand
    /// over its location, and a sandboxed Mac app can't always open that path; so, in order: the file's
    /// contents (a readable copy the system makes) named after the original, the file's path, text.
    @MainActor
    static func loadOne(_ provider: NSItemProvider) async -> Result<DroppedFile, ShareProblem> {
        let url = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            ? await SharedItemLoader.loadURL(provider, type: .fileURL) : nil
        if url?.hasDirectoryPath == true { return .failure(.noText) }
        var firstProblem: ShareProblem?
        if offersFileContents(provider) {
            switch await readFileRepresentation(provider) {
            case .success(var file):
                // Keep the original's name: the path's, the one offered, or the copy's (usually the same).
                file.name = url?.lastPathComponent ?? provider.suggestedName ?? file.name
                return .success(file)
            case .failure(let error): firstProblem = error
            }
        }
        if let url {
            switch read(url) {
            case .success(let file): return .success(file)
            case .failure(let error): firstProblem = firstProblem ?? error
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await SharedItemLoader.loadText(provider), text.contains(where: { !$0.isWhitespace }) {
            return .success(DroppedFile(name: nil, text: text))
        }
        return .failure(firstProblem ?? .noText)
    }

    /// Whether the item carries a file's contents, not just text from a selection or a link. A Finder
    /// drag can offer nothing but the file's type, e.g. only `public.comma-separated-values-text`.
    static func offersFileContents(_ provider: NSItemProvider) -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return true }
        return provider.registeredTypeIdentifiers.contains { identifier in
            guard let type = UTType(identifier), type.conforms(to: .data), !type.conforms(to: .url) else { return false }
            // Plain text without a name is a selection; a named item, or a more specific type
            // (CSV, source code, JSON…), is a file.
            return provider.suggestedName != nil || (type != .plainText && type != .utf8PlainText)
        }
    }

    /// The dropped file's contents, copied by the system so the app may read it.
    @MainActor
    static func readFileRepresentation(_ provider: NSItemProvider) async -> Result<DroppedFile, ShareProblem> {
        let type = provider.registeredTypeIdentifiers.first { $0 != UTType.fileURL.identifier
            && UTType($0)?.conforms(to: .data) == true } ?? UTType.data.identifier
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                // The copy only lasts until this returns, so it's read here.
                guard let url else { return continuation.resume(returning: .failure(.noText)) }
                continuation.resume(returning: read(url))
            }
        }
    }

    /// A dropped file as code: text only (no binaries such as images or apps), up to the share limit.
    static func read(_ url: URL) -> Result<DroppedFile, ShareProblem> {
        if url.hasDirectoryPath { return .failure(.noText) }
        switch SharedItemLoader.readTextFile(url) {
        case .success(let text):
            // Text decoding accepts some binaries; a NUL character means it isn't code.
            guard !text.contains("\u{0}"), text.contains(where: { !$0.isWhitespace }) else { return .failure(.noText) }
            return .success(DroppedFile(name: url.lastPathComponent, text: text))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Shown when nothing usable was dropped.
    public static func message(for problem: ShareProblem) -> String {
        switch problem {
        case .noText: "Drop a code or text file, or some text. Images, apps and folders can't be saved as snippets."
        case .tooLarge: problem.message
        }
    }
}
