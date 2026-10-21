import Foundation
import os

/// A small rolling log of what the app did (requests and their status, sync, scans, the offline
/// queue), kept on the device for bug reports. Never records request bodies, search text,
/// snippet code or credentials. Shared through the App Group so extensions add to it too.
public final class AppLog: @unchecked Sendable {
    public static let shared: AppLog = {
        let container = AppEnvironment.appGroupID
            .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? URL.applicationSupportDirectory
        return AppLog(directory: container.appending(path: "Logs"))
    }()

    public let directory: URL
    private let maxEntries: Int
    private let lock = NSLock()
    private let logger = Logger(subsystem: "me.suryajs.bytecache", category: "app")
    private var file: URL { directory.appending(path: "recent.log") }

    public init(directory: URL, maxEntries: Int = 400) {
        self.directory = directory
        self.maxEntries = maxEntries
    }

    public func record(_ category: String, _ message: String) {
        let line = "\(Self.timestamp()) [\(category)] \(message.replacingOccurrences(of: "\n", with: " "))"
        logger.info("\(line, privacy: .private)")
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var lines = readLines()
        lines.append(line)
        // Rewrite only when well over the limit, so most records are a cheap append.
        if lines.count > maxEntries * 2 || lines.count == 1 || !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            try? lines.suffix(maxEntries).joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
        } else if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        }
    }

    /// The newest entries, oldest first.
    public func entries() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(readLines().suffix(maxEntries))
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: file)
    }

    private func readLines() -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: .now)
    }
}
