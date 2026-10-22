import ByteCacheCore
import CryptoKit
import Foundation
import Observation

/// One Explain result kept for a snippet (CP-79).
public struct AINote: Codable, Equatable, Sendable {
    /// The server's cache key, so notes from different servers don't mix.
    public var server: String
    public var snippetID: Int
    public var text: String
    /// A fingerprint of the code that was explained.
    public var codeFingerprint: String
    public var created: Date

    /// The snippet's code changed since this was written.
    public func isStale(for code: String) -> Bool { codeFingerprint != AINoteStore.fingerprint(code) }
}

/// AI Notes: Explain results kept under the code. Saved on the device and, with iCloud Sync on, in iCloud
/// key-value storage (one key per note) so they follow the person to their other devices. Never sent to
/// the ByteStash server. Keeps the newest `AppSettings.aiNotesLimit`; the oldest go first.
@MainActor @Observable
public final class AINoteStore {
    public static let limits = [25, 50, 100]
    /// Keeps 100 notes well inside iCloud key-value storage's 1 MB.
    public static let maxCharacters = 3_000
    nonisolated static let keyPrefix = "ainote."

    public private(set) var notes: [String: AINote] = [:]

    @ObservationIgnored private let file: URL
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let cloud: (any KeyValueSyncStore)?
    @ObservationIgnored private var observer: NSObjectProtocol?

    public init(directory: URL, settings: AppSettings, cloud: (any KeyValueSyncStore)?) {
        file = directory.appending(path: "ai-notes.json")
        self.settings = settings
        self.cloud = cloud
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: AINote].self, from: data) {
            notes = saved
        }
    }

    /// Where the app keeps them: the shared container, like the activity log.
    public static var defaultDirectory: URL {
        AppEnvironment.appGroupID
            .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? URL.applicationSupportDirectory
    }

    public var count: Int { notes.count }
    /// Roughly how much space they take.
    public var byteSize: Int { notes.values.reduce(0) { $0 + $1.text.utf8.count + 120 } }

    public func note(server: String, snippetID: Int) -> AINote? { notes[Self.key(server, snippetID)] }

    public func save(_ text: String, code: String, server: String, snippetID: Int, date: Date = Date()) {
        let note = AINote(server: server, snippetID: snippetID, text: String(text.prefix(Self.maxCharacters)),
                          codeFingerprint: Self.fingerprint(code), created: date)
        let key = Self.key(server, snippetID)
        notes[key] = note
        push(key, note)
        trim()
        persist()
    }

    public func delete(server: String, snippetID: Int) {
        let key = Self.key(server, snippetID)
        notes[key] = nil
        remove(key)
        persist()
    }

    public func clearAll() {
        for key in notes.keys { remove(key) }
        notes = [:]
        persist()
    }

    /// Takes in notes from other devices and follows their changes. Call once at launch.
    public func start() {
        pull()
        guard observer == nil, let name = cloud?.externalChangeNotification else { return }
        observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            let changed = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated { self?.remoteChanged(keys: changed) }
        }
    }

    /// Another device changed these keys: a note that's gone there (deleted, cleared) goes here too.
    func remoteChanged(keys: [String]) {
        guard syncing, let cloud else { return }
        var removed = false
        for key in keys where key.hasPrefix(Self.keyPrefix) && cloud.data(forKey: key) == nil && notes[key] != nil {
            notes[key] = nil
            removed = true
        }
        if removed { persist() }
        pull()
    }

    /// The limit went down: drop the oldest.
    public func applyLimit() {
        trim()
        persist()
    }

    // MARK: Private

    private var syncing: Bool { cloud != nil && settings.iCloudSyncEnabled }

    private func pull() {
        guard syncing, let cloud else { return }
        cloud.synchronize()
        var remote: [String: AINote] = [:]
        for key in cloud.allKeys where key.hasPrefix(Self.keyPrefix) {
            if let data = cloud.data(forKey: key), let note = try? JSONDecoder().decode(AINote.self, from: data) {
                remote[key] = note
            }
        }
        var changed = false
        for (key, note) in remote where notes[key].map({ $0.created < note.created }) ?? true {
            notes[key] = note
            changed = true
        }
        if changed {
            trim()
            persist()
        }
    }

    private func push(_ key: String, _ note: AINote) {
        guard syncing, let data = try? JSONEncoder().encode(note) else { return }
        cloud?.setData(data, forKey: key)
    }

    private func remove(_ key: String) {
        guard syncing else { return }
        cloud?.removeValue(forKey: key)
    }

    private func trim() {
        let extra = notes.count - settings.aiNotesLimit
        guard extra > 0 else { return }
        for (key, _) in notes.sorted(by: { $0.value.created < $1.value.created }).prefix(extra) {
            notes[key] = nil
            remove(key)
        }
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(notes).write(to: file, options: .atomic)
    }

    nonisolated static func key(_ server: String, _ snippetID: Int) -> String {
        // iCloud keys are limited in length; a server address can be long.
        let digest = SHA256.hash(data: Data(server.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(keyPrefix)\(digest).\(snippetID)"
    }

    nonisolated static func fingerprint(_ code: String) -> String {
        SHA256.hash(data: Data(code.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
