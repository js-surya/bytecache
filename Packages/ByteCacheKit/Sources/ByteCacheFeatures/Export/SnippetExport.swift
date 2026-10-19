import ByteCacheCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Saving snippets as files: one fragment → `<title>.<ext>`; several → a folder named after the title.
public enum SnippetExport {
    private static let extensions: [String: String] = [
        "javascript": "js", "typescript": "ts", "html": "html", "css": "css", "php": "php", "webassembly": "wat",
        "c": "c", "cpp": "cpp", "csharp": "cs", "vba": "bas", "rust": "rs", "go": "go", "java": "java", "kotlin": "kt",
        "scala": "scala", "groovy": "groovy", "python": "py", "ruby": "rb", "perl": "pl", "lua": "lua", "bash": "sh",
        "powershell": "ps1", "batch": "bat", "sql": "sql", "mongodb": "js", "markdown": "md", "yaml": "yaml",
        "json": "json", "xml": "xml", "toml": "toml", "ini": "ini", "conf": "conf", "vimscript": "vim",
        "terraform": "tf", "dockerfile": "dockerfile", "kubernetes": "yaml", "swift": "swift", "r": "r", "julia": "jl",
        "dart": "dart", "elm": "elm", "apex": "cls", "solidity": "sol", "vyper": "vy", "verilog": "v",
        "systemverilog": "sv", "latex": "tex", "matlab": "m", "graphql": "graphql", "cypher": "cypher", "abap": "abap",
        "x3": "src", "plaintext": "txt",
    ]

    public static func fileExtension(for language: String) -> String {
        extensions[language] ?? "txt"
    }

    /// A name every file system accepts: no path separators or reserved characters, no leading dots, ≤ 100 chars.
    public static func safeName(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        var name = String(String.UnicodeScalarView(raw.unicodeScalars.map { forbidden.contains($0) ? "-" : $0 }))
        name = name.trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(100)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "snippet" : name
    }

    /// File name for a snippet saved as a single file (first fragment).
    public static func fileName(for snippet: Snippet) -> String {
        let fragment = snippet.fragments.sorted { $0.position < $1.position }.first
        return fileName(base: snippet.title, language: fragment?.language ?? "plaintext")
    }

    /// `base` with the language's extension, unless it already has it. Dockerfiles are just "Dockerfile".
    static func fileName(base: String, language: String) -> String {
        if language == "dockerfile" { return "Dockerfile" }
        let name = safeName(base)
        let ext = fileExtension(for: language)
        return (name as NSString).pathExtension.lowercased() == ext ? name : "\(name).\(ext)"
    }

    public static func contentType(for snippet: Snippet) -> UTType {
        guard snippet.fragments.count == 1, let language = snippet.fragments.first?.language else {
            return snippet.fragments.count > 1 ? .folder : .plainText
        }
        return UTType(filenameExtension: fileExtension(for: language), conformingTo: .text) ?? .plainText
    }

    public static func defaultFilename(for snippet: Snippet) -> String {
        snippet.fragments.count > 1 ? safeName(snippet.title) : fileName(for: snippet)
    }

    /// The whole snippet: a file, or a folder with one file per fragment (names made unique).
    public static func fileWrapper(for snippet: Snippet) -> FileWrapper {
        let fragments = snippet.fragments.sorted { $0.position < $1.position }
        guard fragments.count > 1 else {
            let file = FileWrapper(regularFileWithContents: Data((fragments.first?.code ?? "").utf8))
            file.preferredFilename = fileName(for: snippet)
            return file
        }
        var used = Set<String>()
        var files: [String: FileWrapper] = [:]
        for (index, fragment) in fragments.enumerated() {
            let base = fragment.fileName.trimmingCharacters(in: .whitespaces).isEmpty ? "file\(index + 1)" : fragment.fileName
            let hasExtension = !(base as NSString).pathExtension.isEmpty
            var name = hasExtension ? safeName(base) : fileName(base: base, language: fragment.language)
            let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            var counter = 2
            while used.contains(name.lowercased()) {
                name = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
                counter += 1
            }
            used.insert(name.lowercased())
            let file = FileWrapper(regularFileWithContents: Data(fragment.code.utf8))
            file.preferredFilename = name
            files[name] = file
        }
        let folder = FileWrapper(directoryWithFileWrappers: files)
        folder.preferredFilename = safeName(snippet.title)
        return folder
    }

    /// One fragment on its own: its file name (with an extension), or the snippet title.
    public static func fileWrapper(for fragment: Fragment, snippetTitle: String) -> (FileWrapper, UTType) {
        let base = fragment.fileName.trimmingCharacters(in: .whitespaces).isEmpty || fragment.fileName == "main"
            ? snippetTitle : fragment.fileName
        let hasExtension = !(base as NSString).pathExtension.isEmpty
        let name = hasExtension ? safeName(base) : fileName(base: base, language: fragment.language)
        let file = FileWrapper(regularFileWithContents: Data(fragment.code.utf8))
        file.preferredFilename = name
        let type = UTType(filenameExtension: (name as NSString).pathExtension, conformingTo: .text) ?? .plainText
        return (file, type)
    }
}

/// Hands a prepared file or folder to `fileExporter`.
public struct SnippetFileDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.plainText, .folder] }
    let wrapper: FileWrapper

    public init(wrapper: FileWrapper) {
        self.wrapper = wrapper
    }

    public init(configuration: ReadConfiguration) throws {
        wrapper = configuration.file
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper
    }
}

/// A file (or folder) ready for `fileExporter`.
public struct ExportFile {
    public let wrapper: FileWrapper
    public let contentType: UTType
    public var filename: String { wrapper.preferredFilename ?? "snippet" }
}

/// One entry in the Save menu: the whole snippet, or a single file of it.
public struct ExportChoice: Identifiable {
    public let id: String
    public let title: String
    private let make: () -> ExportFile

    init(id: String, title: String, make: @escaping () -> ExportFile) {
        self.id = id
        self.title = title
        self.make = make
    }

    public func export() -> ExportFile { make() }
}

extension SnippetExport {
    /// Single-file snippets: one choice. Several files: "All Files (Folder)", then each file by its saved name.
    public static func choices(for snippet: Snippet) -> [ExportChoice] {
        let whole = ExportChoice(id: "all", title: snippet.fragments.count > 1 ? "All Files (Folder)" : fileName(for: snippet)) {
            ExportFile(wrapper: fileWrapper(for: snippet), contentType: contentType(for: snippet))
        }
        guard snippet.fragments.count > 1 else { return [whole] }
        let files = snippet.fragments.sorted { $0.position < $1.position }.map { fragment in
            let (wrapper, type) = fileWrapper(for: fragment, snippetTitle: snippet.title)
            return ExportChoice(id: "fragment-\(fragment.id)", title: wrapper.preferredFilename ?? "file") {
                ExportFile(wrapper: fileWrapper(for: fragment, snippetTitle: snippet.title).0, contentType: type)
            }
        }
        return [whole] + files
    }
}
