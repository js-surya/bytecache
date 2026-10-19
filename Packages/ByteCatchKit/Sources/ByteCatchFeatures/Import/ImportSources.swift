import ByteCatchCore
import ByteCatchLanguage
import Foundation

/// A snippet waiting to be imported (shown in a preview list with a checkbox).
public struct ImportCandidate: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var title: String
    public var description = ""
    public var categories: [String] = []
    public var fragments: [FragmentDraft]
    public var isSelected = true

    public init(title: String, description: String = "", categories: [String] = [], fragments: [FragmentDraft]) {
        self.title = title
        self.description = description
        self.categories = categories
        self.fragments = fragments
    }

    var draft: SnippetDraft {
        SnippetDraft(title: title, description: description, categories: categories, fragments: fragments, isPublic: false)
    }
}

public struct ImportError: Error, Equatable {
    public let message: String
}

private func detectLanguage(_ code: String, fileName: String?, detector: LanguageDetector) -> String {
    detector.detect(DetectionInput(text: code, fileName: fileName)).best
}

// MARK: GitHub Gist

public enum GistImport {
    public static func gistID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.wholeMatch(of: /[0-9a-f]{20,40}/) != nil { return trimmed }
        guard trimmed.contains("gist.github.com") else { return nil }
        let path = trimmed.split(separator: "#").first.map(String.init) ?? trimmed
        return path.split(separator: "/").reversed().lazy.map(String.init)
            .first { $0.wholeMatch(of: /[0-9a-f]{20,40}/) != nil }
    }

    private struct Gist: Decodable {
        struct File: Decodable {
            let filename: String; let content: String?; let truncated: Bool?; let raw_url: String?; let language: String?
        }
        let description: String?
        let files: [String: File]
    }

    /// One candidate per gist: its description as title, one fragment per file.
    public static func fetch(_ link: String, transport: any HTTPTransport = URLSession.shared,
                             detector: LanguageDetector) async throws -> [ImportCandidate] {
        guard let id = gistID(from: link) else { throw ImportError(message: "Paste a gist link like https://gist.github.com/user/1a2b3c….") }
        let data = try await get(URL(string: "https://api.github.com/gists/\(id)")!, transport: transport)
        guard let gist = try? JSONDecoder().decode(Gist.self, from: data) else {
            throw ImportError(message: "GitHub sent something ByteCatch didn't understand.")
        }
        var fragments: [FragmentDraft] = []
        for file in gist.files.values.sorted(by: { $0.filename < $1.filename }) {
            var code = file.content ?? ""
            if file.truncated == true, let raw = file.raw_url.flatMap(URL.init(string:)) {
                code = String(decoding: try await get(raw, transport: transport), as: UTF8.self)
            }
            // GitHub's own language label first (its files are often named gistfile1.txt).
            let reported = file.language.flatMap { LanguageCatalog.id(forAlias: $0.lowercased()) }.flatMap { $0 == "plaintext" ? nil : $0 }
            fragments.append(FragmentDraft(fileName: file.filename, code: code,
                                           language: reported ?? detectLanguage(code, fileName: file.filename, detector: detector)))
        }
        guard !fragments.isEmpty else { throw ImportError(message: "That gist has no files.") }
        let title = gist.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [ImportCandidate(title: (title?.isEmpty == false ? title : nil) ?? fragments[0].fileName,
                                description: "Imported from gist \(id)", fragments: fragments)]
    }

    private static func get(_ url: URL, transport: any HTTPTransport) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ByteCatch", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw ImportError(message: "Couldn't reach GitHub. Check your connection.")
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 404: throw ImportError(message: "That gist wasn't found. Check the link (secret gists need the full link).")
        case 403, 429: throw ImportError(message: "GitHub's rate limit was reached. Try again in a little while.")
        default: throw ImportError(message: "GitHub returned an error.")
        }
    }
}

// MARK: VS Code snippets

public enum VSCodeSnippetImport {
    private struct Entry: Decodable {
        let body: Body
        let description: String?
        let scope: String?
        enum Body: Decodable {
            case lines([String]), text(String)
            init(from decoder: any Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let lines = try? c.decode([String].self) { self = .lines(lines) } else { self = .text(try c.decode(String.self)) }
            }
            var code: String {
                switch self {
                case .lines(let lines): lines.joined(separator: "\n")
                case .text(let text): text
                }
            }
        }
    }

    /// `.code-snippets` or `<language>.json` (comments and trailing commas allowed, as in VS Code).
    public static func parse(_ data: Data, fileName: String, detector: LanguageDetector) throws -> [ImportCandidate] {
        let cleaned = Data(stripJSONC(String(decoding: data, as: UTF8.self)).utf8)
        guard let entries = try? JSONDecoder().decode([String: Entry].self, from: cleaned) else {
            throw ImportError(message: "\(fileName) isn't a VS Code snippets file.")
        }
        let fileLanguage = LanguageCatalog.id(forAlias: (fileName as NSString).deletingPathExtension)
        let order = keyOrder(in: String(decoding: cleaned, as: UTF8.self))
        return entries.sorted { (order[$0.key] ?? .max) < (order[$1.key] ?? .max) }.map { name, entry in
            let code = entry.body.code
            let scoped = entry.scope?.split(separator: ",").first.flatMap { LanguageCatalog.id(forAlias: $0.trimmingCharacters(in: .whitespaces)) }
            let language = scoped ?? fileLanguage ?? detectLanguage(code, fileName: nil, detector: detector)
            return ImportCandidate(title: name, description: entry.description ?? "", categories: ["vscode"],
                                   fragments: [FragmentDraft(fileName: "snippet", code: code, language: language)])
        }
    }

    /// Top-level key positions, so candidates keep the file's order.
    private static func keyOrder(in json: String) -> [String: Int] {
        var order: [String: Int] = [:]
        var depth = 0, inString = false, escaped = false, keyStart: String.Index?, index = 0
        var i = json.startIndex
        while i < json.endIndex {
            let c = json[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" {
                    inString = false
                    if depth == 1, let start = keyStart {
                        let key = String(json[json.index(after: start)..<i])
                        if order[key] == nil { order[key] = index; index += 1 }
                    }
                    keyStart = nil
                }
            } else if c == "\"" {
                inString = true
                keyStart = depth == 1 && (json[..<i].last(where: { !$0.isWhitespace }).map { $0 == "{" || $0 == "," } ?? false) ? i : nil
            } else if c == "{" || c == "[" { depth += 1 } else if c == "}" || c == "]" { depth -= 1 }
            i = json.index(after: i)
        }
        return order
    }

    /// Removes // and /* */ comments outside strings, and trailing commas.
    static func stripJSONC(_ text: String) -> String {
        var out = "", i = text.startIndex, inString = false, escaped = false
        while i < text.endIndex {
            let c = text[i], next = text.index(after: i) < text.endIndex ? text[text.index(after: i)] : nil
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                i = text.index(after: i)
            } else if c == "\"" {
                inString = true; out.append(c); i = text.index(after: i)
            } else if c == "/", next == "/" {
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
            } else if c == "/", next == "*" {
                i = text.index(i, offsetBy: 2)
                while i < text.endIndex, !(text[i] == "*" && text.index(after: i) < text.endIndex && text[text.index(after: i)] == "/") {
                    i = text.index(after: i)
                }
                if i < text.endIndex { i = text.index(i, offsetBy: 2) }
            } else {
                out.append(c); i = text.index(after: i)
            }
        }
        return out.replacing(/,(\s*[}\]])/) { $0.1 }.description
    }
}

// MARK: Files and folders

public enum FileImport {
    public static let maxBytes = 1_000_000

    /// Every text file under the given files/folders (hidden and binary files skipped).
    public static func candidates(from urls: [URL], detector: LanguageDetector) -> [ImportCandidate] {
        var files: [URL] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                                options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let file = enumerator?.nextObject() as? URL {
                    if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { files.append(file) }
                }
            } else {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }.compactMap { file in
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes,
                  let data = try? Data(contentsOf: file), !data.contains(0),
                  let code = String(data: data, encoding: .utf8) else { return nil }
            let name = file.lastPathComponent
            return ImportCandidate(title: (name as NSString).deletingPathExtension,
                                   fragments: [FragmentDraft(fileName: name, code: code,
                                                             language: detectLanguage(code, fileName: name, detector: detector))])
        }
    }
}

// MARK: Running an import

@MainActor
public struct ImportRunner {
    public struct Result: Equatable { public var created = 0, failed = 0 }
    let session: SessionManager

    public init(session: SessionManager) {
        self.session = session
    }

    public func run(_ candidates: [ImportCandidate]) async -> Result {
        var result = Result()
        guard let client = session.client else { return result }
        for candidate in candidates where candidate.isSelected {
            do {
                _ = try await client.create(candidate.draft)
                result.created += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }
}
