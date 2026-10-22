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

/// The parts of a GitHub release ByteCache uses (its notes, for What's New).
public struct GitHubRelease: Equatable, Sendable {
    public let version: AppVersion
    public let title: String
    public let notes: String
    public let page: URL

    private struct Payload: Decodable {
        let tag_name: String
        let name: String?
        let html_url: URL
        let body: String?
        let draft: Bool
        let prerelease: Bool
    }

    struct NotARelease: Error {}

    static func decode(_ data: Data) throws -> GitHubRelease {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        guard !p.draft, !p.prerelease, let version = AppVersion(p.tag_name) else { throw NotARelease() }
        return GitHubRelease(version: version, title: p.name ?? "ByteCache \(version)", notes: p.body ?? "", page: p.html_url)
    }
}

/// What's New: notices the first launch after an update and fetches that version's notes from its
/// GitHub release. Updates themselves come through TestFlight and the App Store. Sends nothing about
/// the user: one anonymous request after each update.
public final class UpdateChecker: @unchecked Sendable {
    public static let repository = "js-surya/bytecache"
    static let lastRunKey = "updateLastRunVersion"

    private let current: AppVersion
    /// The version being checked against (the running app's).
    public var version: AppVersion { current }
    private let defaults: UserDefaults
    private let transport: any HTTPTransport

    public init(current: AppVersion = .current, defaults: UserDefaults = .standard,
                transport: any HTTPTransport = URLSession.shared) {
        self.current = current
        self.defaults = defaults
        self.transport = transport
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
