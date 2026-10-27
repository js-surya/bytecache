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
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await SharedItemLoader.loadURL(provider, type: .fileURL) {
                switch read(url) {
                case .success(let file): files.append(file)
                case .failure(let error): problem = problem ?? error
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = await SharedItemLoader.loadText(provider), text.contains(where: { !$0.isWhitespace }) {
                files.append(DroppedFile(name: nil, text: text))
            }
        }
        if !files.isEmpty { return .success(files) }
        return .failure(problem ?? .noText)
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
