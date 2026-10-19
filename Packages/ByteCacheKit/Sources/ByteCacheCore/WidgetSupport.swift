import Foundation

/// One snippet as shown in a widget. `code` is kept (capped) so the widget's Copy button works offline.
public struct WidgetSnippet: Codable, Identifiable, Equatable, Sendable {
    public static let previewLines = 6
    public static let maxCodeLength = 20_000

    public let id: Int
    public let title: String
    public let language: String
    public let preview: String
    public let code: String

    public init(_ snippet: Snippet) {
        let first = snippet.fragments.sorted { $0.position < $1.position }.first
        let code = first?.code ?? ""
        id = snippet.id
        title = snippet.title.isEmpty ? "Untitled snippet" : snippet.title
        language = first?.language ?? "plaintext"
        preview = code.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(Self.previewLines).map { String($0.prefix(120)) }.joined(separator: "\n")
        self.code = String(code.prefix(Self.maxCodeLength))
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var serverName: String
    public var pinned: [WidgetSnippet]
    public var recent: [WidgetSnippet]
    public var updatedAt: Date

    public init(serverName: String, pinned: [WidgetSnippet], recent: [WidgetSnippet], updatedAt: Date = Date()) {
        self.serverName = serverName
        self.pinned = pinned
        self.recent = recent
        self.updatedAt = updatedAt
    }

    public func snippet(id: Int) -> WidgetSnippet? {
        (pinned + recent).first { $0.id == id }
    }
}

/// The snapshot file shared by the app (writer) and the widget extension (reader), in the App Group.
public struct WidgetSnapshotStore: Sendable {
    private let file: URL

    public init(directory: URL? = nil) {
        let dir = directory
            ?? AppEnvironment.appGroupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? URL.applicationSupportDirectory
        file = dir.appending(path: "widget-snapshot.json")
    }

    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

/// `bytecache://` links used by widgets, controls and shortcuts.
public enum DeepLink: Equatable, Sendable {
    case snippet(Int)
    case captureClipboard
    case scanCode

    public static let scheme = "bytecache"

    public init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let parts = [url.host() ?? ""] + url.pathComponents.filter { $0 != "/" }
        switch (parts.first, parts.dropFirst().first) {
        case ("snippet", let id?): guard let n = Int(id) else { return nil }; self = .snippet(n)
        case ("capture", "clipboard"): self = .captureClipboard
        case ("capture", "scan"): self = .scanCode
        default: return nil
        }
    }

    public var url: URL {
        switch self {
        case .snippet(let id): URL(string: "\(Self.scheme)://snippet/\(id)")!
        case .captureClipboard: URL(string: "\(Self.scheme)://capture/clipboard")!
        case .scanCode: URL(string: "\(Self.scheme)://capture/scan")!
        }
    }
}

/// A capture asked for by a control or shortcut that runs outside the app; the app picks it up when it opens.
public enum PendingCapture {
    static let key = "pendingCapture"

    public static func request(_ link: DeepLink, in defaults: UserDefaults = AppEnvironment.sharedDefaults) {
        defaults.set(link.url.absoluteString, forKey: key)
    }

    public static func consume(from defaults: UserDefaults = AppEnvironment.sharedDefaults) -> DeepLink? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return URL(string: raw).flatMap(DeepLink.init(url:))
    }
}
