import Foundation
import UniformTypeIdentifiers

/// What another app shared with ByteCache.
public struct SharedPayload: Equatable, Sendable {
    public var text: String
    public var fileName: String?
    public var sourceURL: URL?
    public var pageTitle: String?

    public init(text: String, fileName: String? = nil, sourceURL: URL? = nil, pageTitle: String? = nil) {
        self.text = text
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.pageTitle = pageTitle
    }
}

public enum ShareProblem: Error, Equatable, Sendable {
    case noText, tooLarge

    public var message: String {
        switch self {
        case .noText: "Select the code first, then share."
        case .tooLarge: "That file is too large to save as a snippet (limit 1 MB)."
        }
    }
}

/// Reads text, a web page selection, or a text file from share-extension items.
public enum SharedItemLoader {
    public static let maxFileBytes = 1_000_000

    @MainActor
    public static func load(from items: [NSExtensionItem]) async -> Result<SharedPayload, ShareProblem> {
        var text: String?
        var fileName: String?
        var sourceURL: URL?
        var tooLarge = false
        let title = items.lazy.compactMap { $0.attributedTitle?.string }.first { !$0.isEmpty }

        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await loadURL(provider, type: .fileURL) {
                switch readTextFile(url) {
                case .success(let contents):
                    text = text ?? contents
                    fileName = url.lastPathComponent
                case .failure(.tooLarge): tooLarge = true
                case .failure: break
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = await loadURL(provider, type: .url) {
                sourceURL = sourceURL ?? url
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let shared = await loadText(provider), shared.contains(where: { !$0.isWhitespace }) {
                text = text ?? shared
            }
        }
        if let text {
            return .success(SharedPayload(text: text, fileName: fileName, sourceURL: sourceURL, pageTitle: title))
        }
        return .failure(tooLarge ? .tooLarge : .noText)
    }

    @MainActor static func loadURL(_ provider: NSItemProvider, type: UTType) async -> URL? {
        let item = try? await provider.loadItem(forTypeIdentifier: type.identifier)
        switch item {
        case let url as URL: return url
        case let data as Data: return URL(dataRepresentation: data, relativeTo: nil)
        case let string as String: return URL(string: string)
        default: return nil
        }
    }

    @MainActor static func loadText(_ provider: NSItemProvider) async -> String? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
        switch item {
        case let string as String: return string
        case let string as NSAttributedString: return string.string
        case let data as Data: return String(data: data, encoding: .utf8)
        default: return nil
        }
    }

    static func readTextFile(_ url: URL) -> Result<String, ShareProblem> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileBytes else { return .failure(.tooLarge) }
        guard let data = try? Data(contentsOf: url), let text = decodeText(data) else {
            return .failure(.noText)
        }
        return .success(text)
    }

    /// Text in the encodings code and CSV files come in: UTF-8, UTF-16 with a byte-order mark (Excel's
    /// "Unicode Text"), or Windows Latin (Excel's CSV and older editors). Nil for binary data
    /// (images, apps), which has control bytes text doesn't (CP-92: a CSV was refused).
    static func decodeText(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        guard looksLikeText(data) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }

    /// No NUL bytes and almost no other control characters (tabs and line breaks are fine).
    static func looksLikeText(_ data: Data) -> Bool {
        var control = 0
        for byte in data {
            if byte == 0 { return false }
            if byte < 0x20, byte != 0x09, byte != 0x0A, byte != 0x0D, byte != 0x0C { control += 1 }
        }
        return control * 200 <= data.count
    }
}
