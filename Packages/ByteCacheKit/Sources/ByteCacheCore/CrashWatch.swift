import Foundation

/// Notices when the last session ended unexpectedly, so the next launch can offer a bug report, and
/// keeps the newest crash and hang diagnostics the system delivers (MetricKit; see DiagnosticsCollector).
///
/// A marker file exists while the app is in the foreground. Leaving the foreground or quitting
/// removes it, so being closed later (swiped away, or ended by the system in the background) is
/// normal; a marker still there at launch means the app ended while it was open.
public final class CrashWatch: @unchecked Sendable {
    public static let shared = CrashWatch(directory: AppLog.shared.directory)

    public struct Diagnostic: Equatable, Sendable {
        public let date: Date
        public let summary: String
        /// MetricKit's payload: call stacks as binary names and addresses, nothing personal.
        public let json: Data
    }

    public private(set) var endedUnexpectedly = false

    private let directory: URL
    private let keepDiagnostics: Int
    private let lock = NSLock()
    private var marker: URL { directory.appending(path: "app-session.running") }
    private var diagnostics: URL { directory.appending(path: "Diagnostics") }

    public init(directory: URL, keepDiagnostics: Int = 5) {
        self.directory = directory
        self.keepDiagnostics = keepDiagnostics
    }

    /// Call once at launch.
    public func launched() {
        endedUnexpectedly = FileManager.default.fileExists(atPath: marker.path(percentEncoded: false))
        enteredForeground()
    }

    public func enteredForeground() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data().write(to: marker)
    }

    public func enteredBackground() {
        try? FileManager.default.removeItem(at: marker)
    }

    public func terminated() {
        enteredBackground()
    }

    // MARK: Diagnostics

    public func saveDiagnostic(summary: String, json: Data, date: Date) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        let name = "\(Int(date.timeIntervalSince1970 * 1000))"
        try? json.write(to: diagnostics.appending(path: "\(name).json"))
        try? Data(summary.utf8).write(to: diagnostics.appending(path: "\(name).txt"))
        for old in stamps().dropLast(keepDiagnostics) {
            try? FileManager.default.removeItem(at: diagnostics.appending(path: "\(old).json"))
            try? FileManager.default.removeItem(at: diagnostics.appending(path: "\(old).txt"))
        }
    }

    public func latestDiagnostic() -> Diagnostic? {
        lock.lock()
        defer { lock.unlock() }
        guard let newest = stamps().last,
              let json = try? Data(contentsOf: diagnostics.appending(path: "\(newest).json")),
              let summary = try? String(contentsOf: diagnostics.appending(path: "\(newest).txt"), encoding: .utf8)
        else { return nil }
        return Diagnostic(date: Date(timeIntervalSince1970: Double(newest) / 1000), summary: summary, json: json)
    }

    var diagnosticCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stamps().count
    }

    /// Saved diagnostics, oldest first.
    private func stamps() -> [Int] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: diagnostics.path(percentEncoded: false))) ?? []
        return Set(files.compactMap { Int($0.split(separator: ".").first ?? "") }).sorted()
    }
}
