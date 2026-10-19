import Foundation

/// A release version such as 1.2.0 ("v1.2", "1.2.0 (14)" and "1.2" are read the same way).
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let core = trimmed.drop { $0 == "v" || $0 == "V" }.prefix { $0.isNumber || $0 == "." }
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        var parts = numbers.compactMap { $0 }
        while parts.count < 3 { parts.append(0) }
        self.parts = parts
    }

    /// The running app's version (CFBundleShortVersionString).
    public static var current: AppVersion {
        AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") ?? AppVersion("0")!
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
    public static func == (a: AppVersion, b: AppVersion) -> Bool { a.parts == b.parts }
}

/// The parts of a GitHub release ByteCache uses.
public struct GitHubRelease: Equatable, Sendable {
    public enum Platform: Sendable { case iOS, macOS }

    public let version: AppVersion
    public let title: String
    public let notes: String
    public let page: URL
    let assets: [String: URL]

    /// The file to download on this kind of device (the .ipa covers iPhone and iPad).
    public func download(for platform: Platform) -> URL? {
        let suffix = platform == .iOS ? "-iOS.ipa" : "-macOS.zip"
        return assets.first { $0.key.hasSuffix(suffix) }?.value
    }

    private struct Payload: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let name: String?
        let html_url: URL
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    struct NotARelease: Error {}

    static func decode(_ data: Data) throws -> GitHubRelease {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        guard !p.draft, !p.prerelease, let version = AppVersion(p.tag_name) else { throw NotARelease() }
        return GitHubRelease(version: version, title: p.name ?? "ByteCache \(version)", notes: p.body ?? "", page: p.html_url,
                             assets: Dictionary(p.assets.map { ($0.name, $0.browser_download_url) }, uniquingKeysWith: { a, _ in a }))
    }
}

public enum UpdateResult: Equatable, Sendable {
    case available(GitHubRelease)
    case upToDate
    /// Automatic checks run at most once a day.
    case skippedRecentlyChecked
    /// Offline, rate-limited or an unexpected answer; automatic checks stay quiet about it.
    case failed
}

/// Checks GitHub Releases for a newer ByteCache. Sideloaded apps can't update themselves, so this
/// is how people hear about new versions. Sends nothing about the user: one anonymous request a day.
public final class UpdateChecker: @unchecked Sendable {
    public static let repository = "js-surya/bytecache"
    static let lastCheckKey = "updateLastCheck", skippedKey = "updateSkippedVersion", lastRunKey = "updateLastRunVersion"

    private let current: AppVersion
    /// The version being checked against (the running app's).
    public var version: AppVersion { current }
    private let defaults: UserDefaults
    private let transport: any HTTPTransport
    private let now: () -> Date

    public init(current: AppVersion = .current, defaults: UserDefaults = .standard,
                transport: any HTTPTransport = URLSession.shared, now: @escaping () -> Date = Date.init) {
        self.current = current
        self.defaults = defaults
        self.transport = transport
        self.now = now
    }

    /// `force` (Check Now) ignores the once-a-day limit and skipped versions.
    public func check(force: Bool) async -> UpdateResult {
        if !force, let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           now().timeIntervalSince(last) < 24 * 3600 {
            return .skippedRecentlyChecked
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!,
                                 timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ByteCache/\(current)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await transport.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? GitHubRelease.decode(data) else {
            AppLog.shared.record("update", "check failed")
            return .failed
        }
        defaults.set(now(), forKey: Self.lastCheckKey)
        AppLog.shared.record("update", "latest \(release.version), running \(current)")
        guard release.version > current else { return .upToDate }
        if !force, let skipped = defaults.string(forKey: Self.skippedKey).flatMap(AppVersion.init), release.version <= skipped {
            return .upToDate
        }
        return .available(release)
    }

    /// Don't offer this version again (a later one still is).
    public func skip(_ version: AppVersion) {
        defaults.set(version.description, forKey: Self.skippedKey)
    }

    /// True once, on the first launch after an update (not on a first install).
    public func takeWhatsNew() -> Bool {
        let previous = defaults.string(forKey: Self.lastRunKey).flatMap(AppVersion.init)
        defaults.set(current.description, forKey: Self.lastRunKey)
        guard let previous else { return false }
        return current > previous
    }

    /// The notes of the version that's running, for What's New.
    public func currentRelease() async -> GitHubRelease? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/tags/v\(current)")!,
                                 timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await transport.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? GitHubRelease.decode(data)
    }
}
