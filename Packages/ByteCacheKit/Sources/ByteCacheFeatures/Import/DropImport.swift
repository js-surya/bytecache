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
    public static let types: [UTType] = [.fileURL, .plainText]
    /// More files than this in one drop is more likely a mistake than a snippet.
    public static let maxFiles = 20

    @MainActor
    public static func load(_ providers: [NSItemProvider]) async -> Result<[DroppedFile], ShareProblem> {
        var files: [DroppedFile] = []
        var problem: ShareProblem?
        for provider in providers.prefix(maxFiles) {
            let types = provider.registeredTypeIdentifiers.joined(separator: ", ")
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                // A sandboxed Mac app can't always open the dragged file's path, so the file itself is
                // asked for first (the system hands over a readable copy); the path is the fallback.
                let url = await SharedItemLoader.loadURL(provider, type: .fileURL)
                var result = await readFileRepresentation(provider)
                if case .success(var file) = result, let url, !url.hasDirectoryPath {
                    file.name = url.lastPathComponent // the copy has a generic name; keep the original's
                    result = .success(file)
                } else if case .failure = result, let url {
                    result = read(url)
                }
                switch result {
                case .success(let file): files.append(file)
                case .failure(let error):
                    AppLog.shared.record("drop", "couldn't read a dropped file (\(error)); types: \(types)")
                    problem = problem ?? error
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = await SharedItemLoader.loadText(provider), text.contains(where: { !$0.isWhitespace }) {
                files.append(DroppedFile(name: nil, text: text))
            }
        }
        if !files.isEmpty { return .success(files) }
        return .failure(problem ?? .noText)
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
