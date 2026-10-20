import Foundation
import Security

/// One snippet as shown in a widget. `code` is kept (capped) so the widget's Copy button works offline.
public struct WidgetSnippet: Codable, Identifiable, Equatable, Sendable {
    public static let previewLines = 6
    public static let maxCodeLength = 20_000

    public let id: Int
    public let title: String
    public let language: String
    public let preview: String
    public let code: String

    init(id: Int, title: String, language: String, preview: String, code: String) {
        self.id = id
        self.title = title
        self.language = language
        self.preview = preview
        self.code = code
    }

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
    /// Signed in but the snippets couldn't be loaded (e.g. "Can't reach the server"). Optional: absent
    /// in snapshots written by earlier versions.
    public var problem: String?
    /// What a configurable widget can show (Edit Widget), and the snippets for each, by source id.
    /// Optional: absent in snapshots written by earlier versions.
    public var sources: [WidgetSource]?
    public var lists: [String: [WidgetSnippet]]?

    public init(serverName: String, pinned: [WidgetSnippet], recent: [WidgetSnippet], updatedAt: Date = Date(),
                problem: String? = nil, sources: [WidgetSource]? = nil, lists: [String: [WidgetSnippet]]? = nil) {
        self.serverName = serverName
        self.pinned = pinned
        self.recent = recent
        self.updatedAt = updatedAt
        self.problem = problem
        self.sources = sources
        self.lists = lists
    }

    public func snippet(id: Int) -> WidgetSnippet? {
        (pinned + recent + (lists ?? [:]).values.flatMap { $0 }).first { $0.id == id }
    }

    /// The snippets for one source.
    public func list(for source: WidgetSource) -> [WidgetSnippet] {
        switch source.kind {
        case .recent: recent
        case .pinned: pinned
        default: lists?[source.id] ?? []
        }
    }
}

/// What a configurable widget shows: recent, pinned or favorite snippets, a Smart Group, a tag or a language.
public struct WidgetSource: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case recent, pinned, favorites, smartGroup, tag, language
    }

    public var kind: Kind
    /// The Smart Group id, tag or language; empty for the fixed lists.
    public var value: String
    public var title: String

    public var id: String { "\(kind.rawValue):\(value)" }

    public init(kind: Kind, value: String = "", title: String) {
        self.kind = kind
        self.value = value
        self.title = title
    }

    public static let recent = WidgetSource(kind: .recent, title: "Recent")
    public static let pinned = WidgetSource(kind: .pinned, title: "Pinned")
    public static let favorites = WidgetSource(kind: .favorites, title: "Favorites")
}

/// What the widget can see of the app's data.
public enum WidgetSnapshotState: Equatable, Sendable {
    case snapshot(WidgetSnapshot)
    case signedOut
    /// This install gives the app and the widget nothing to share (no App Group, no shared keychain).
    case unavailable
}

/// The snapshot shared by the app (writer) and the widget extension (reader). Normally a file in the
/// App Group; installs without one (some sideloading tools) fall back to an item in the shared keychain.
public struct WidgetSnapshotStore: Sendable {
    private enum Place: Sendable {
        case file(URL)
        case keychain(KeychainBlob)
        /// Not shared: the app writes to its own folder, which the widget can't read.
        case privateFile(URL)
    }

    private let place: Place

    /// The keychain copy keeps each snippet's code short, to stay a modest size.
    static let keychainCodeLimit = 4_000
    private static let signedOutMarker = Data("signed-out".utf8)

    public init(directory: URL? = nil) {
        if let directory {
            place = .file(directory.appending(path: "widget-snapshot.json"))
        } else if let group = AppEnvironment.appGroupID,
                  let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            place = .file(container.appending(path: "widget-snapshot.json"))
        } else if let keychainGroup = AppEnvironment.keychainGroup {
            place = .keychain(KeychainBlob(service: "app.bytecache.widget", account: "snapshot", accessGroup: keychainGroup))
        } else {
            place = .privateFile(URL.applicationSupportDirectory.appending(path: "widget-snapshot.json"))
        }
    }

    /// For tests: the keychain path with a given item.
    init(keychain: KeychainBlob) {
        place = .keychain(keychain)
    }

    /// How the app shares the snapshot with the widget, for Settings → About.
    public var sharing: String {
        switch place {
        case .file: "App Group"
        case .keychain: "Shared keychain"
        case .privateFile: "Not available"
        }
    }

    public func state() -> WidgetSnapshotState {
        switch place {
        case .file(let url):
            guard let data = try? Data(contentsOf: url) else { return .signedOut }
            return (try? JSONDecoder().decode(WidgetSnapshot.self, from: data)).map(WidgetSnapshotState.snapshot) ?? .signedOut
        case .keychain(let blob):
            // No item at all means the app's writes never reach the widget.
            guard let data = blob.read() else { return .unavailable }
            if data == Self.signedOutMarker { return .signedOut }
            return (try? JSONDecoder().decode(WidgetSnapshot.self, from: data)).map(WidgetSnapshotState.snapshot) ?? .signedOut
        case .privateFile:
            return .unavailable
        }
    }

    public func read() -> WidgetSnapshot? {
        if case .snapshot(let snapshot) = state() { return snapshot }
        return nil
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        switch place {
        case .file(let url), .privateFile(let url):
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        case .keychain(let blob):
            var compact = snapshot
            compact.pinned = snapshot.pinned.map { $0.capped(Self.keychainCodeLimit) }
            compact.recent = snapshot.recent.map { $0.capped(Self.keychainCodeLimit) }
            compact.lists = snapshot.lists?.mapValues { $0.map { $0.capped(Self.keychainCodeLimit) } }
            let status = blob.write(try JSONEncoder().encode(compact))
            guard status == errSecSuccess else { throw KeychainBlobError(status: status) }
        }
    }

    public func clear() throws {
        switch place {
        case .file(let url), .privateFile(let url):
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        case .keychain(let blob):
            // An explicit marker, so the widget can tell "signed out" from "can't share".
            blob.write(Self.signedOutMarker)
        }
    }
}

public struct KeychainBlobError: Error, Equatable {
    public let status: OSStatus
}

extension WidgetSnippet {
    /// The same snippet with its code cut to `limit` characters.
    public func capped(_ limit: Int) -> WidgetSnippet {
        WidgetSnippet(id: id, title: title, language: language, preview: preview, code: String(code.prefix(limit)))
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
