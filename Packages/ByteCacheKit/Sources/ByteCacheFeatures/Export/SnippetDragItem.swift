import ByteCacheCore
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A snippet dragged out of the list (CP-92): its code for editors, chats and other apps, or the
/// file (a folder for a snippet with several files) for Finder and Files, named as Save File names it.
public struct SnippetDragItem: Transferable {
    public let snippet: Snippet

    public init(_ snippet: Snippet) {
        self.snippet = snippet
    }

    /// Every file's code, in order, as Copy gives it.
    public var code: String {
        snippet.fragments.sorted { $0.position < $1.position }.map(\.code).joined(separator: "\n\n")
    }

    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.code)
        FileRepresentation(exportedContentType: .data) { item in
            SentTransferredFile(try item.writeFile())
        }
        .suggestedFileName { SnippetExport.defaultFilename(for: $0.snippet) }
    }

    /// Writes the snippet to a fresh temporary folder and returns its file (or folder).
    func writeFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Drag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let wrapper = SnippetExport.fileWrapper(for: snippet)
        let url = folder.appending(path: wrapper.preferredFilename ?? "snippet")
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }
}
