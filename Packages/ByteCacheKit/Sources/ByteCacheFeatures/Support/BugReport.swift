import ByteCacheCore
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Removes anything private from text before it leaves the device in a bug report.
public enum LogScrubber {
    private static let rules: [(pattern: String, replacement: String)] = [
        (#"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer <token>"),
        (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, "<token>"),
        (#"(?i)(x-api-key|api[_-]?key|token|password)(["']?\s*[:=]\s*["']?)[^\s"',]+"#, "$1$2<redacted>"),
        (#"\b[a-fA-F0-9]{32,}\b"#, "<key>"),
        (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<email>"),
        (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "<ip>"),
        (#"://[^/\s:@]+:[^/\s@]+@"#, "://<credentials>@"),
    ]

    /// `serverHosts`: the user's server addresses, replaced with `<server>`.
    public static func scrub(_ text: String, serverHosts: [String]) -> String {
        // Emails and tokens first: replacing a server address inside "me@my.server" would leave "me@".
        var result = text
        for rule in rules {
            result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement, options: .regularExpression)
        }
        for host in serverHosts where !host.isEmpty {
            result = result.replacingOccurrences(of: host, with: "<server>", options: .caseInsensitive)
        }
        return SecretScanner.redact(result)
    }
}

/// What a bug report says about the device.
public struct DeviceInfo: Equatable, Sendable {
    public var app: String
    public var os: String
    public var model: String
    public var platform: String

    public init(app: String, os: String, model: String, platform: String) {
        self.app = app
        self.os = os
        self.model = model
        self.platform = platform
    }

    @MainActor
    public static var current: DeviceInfo {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #if os(macOS)
        let model = Self.sysctl("hw.model") ?? machine
        return DeviceInfo(app: AboutText.versionWithBuild, os: "macOS \(version)", model: model, platform: "Mac")
        #else
        let simulator = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        return DeviceInfo(app: AboutText.versionWithBuild, os: "\(pad ? "iPadOS" : "iOS") \(version)",
                          model: simulator.map { "\($0) (Simulator)" } ?? machine, platform: pad ? "iPad" : "iPhone")
        #endif
    }

    #if os(macOS)
    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    #endif
}

/// A bug report, sent as a pre-filled GitHub issue or an email (no account or token in the app: the
/// user reviews and sends it themselves). Logs too long for a link go into a file to attach.
public struct BugReport: Sendable {
    public static let repository = "js-surya/bytecache"
    /// Browsers and GitHub handle links up to about 8 KB.
    public static let maxLinkLength = 7_500
    public static let logFileName = "ByteCache-logs.txt"

    public var title: String
    public var whatHappened: String
    public var steps: String
    public var device: DeviceInfo
    /// Already scrubbed.
    public var logs: [String]
    /// App details (ReportContext): settings and state, nothing personal.
    public var context: [String]
    /// The newest crash or hang report from the system (MetricKit JSON), for the log file.
    public var diagnostic: String?

    public init(title: String, whatHappened: String, steps: String, device: DeviceInfo, logs: [String],
                context: [String] = [], diagnostic: String? = nil) {
        self.title = title
        self.whatHappened = whatHappened
        self.steps = steps
        self.device = device
        self.logs = logs
        self.context = context
        self.diagnostic = diagnostic
    }

    public var issueTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bug report" : trimmed
    }

    public var versions: String { "ByteCache \(device.app), \(device.os), \(device.model)" }

    /// App details, then the activity, as one block.
    private var details: [String] {
        context + (context.isEmpty || logs.isEmpty ? [] : [""]) + logs
    }

    private var logBlock: String { "```\n" + details.joined(separator: "\n") + "\n```" }

    public var logsFitInLink: Bool { link(logs: logBlock).absoluteString.count <= Self.maxLinkLength }

    public func issueURL() -> URL {
        if details.isEmpty { return link(logs: "") }
        return logsFitInLink ? link(logs: logBlock)
            : link(logs: "Recent logs are in the attached file \(Self.logFileName) (drag it into this box).")
    }

    /// The file to attach when the logs don't fit in the link.
    public var logFileText: String {
        """
        ByteCache bug report logs
        \(versions)
        Created \(ISO8601DateFormatter().string(from: .now))

        \(details.joined(separator: "\n"))
        \(diagnostic.map { "\n\nCrash or hang report from the system (MetricKit):\n\($0)\n" } ?? "")
        """
    }

    /// The whole report as text, for email and Copy Report.
    public var plainText: String {
        var parts = ["# \(issueTitle)", "What happened:\n\(whatHappened)"]
        if steps.contains(where: { !$0.isWhitespace }) { parts.append("Steps to reproduce:\n\(steps)") }
        parts.append("Versions: \(versions)")
        if !context.isEmpty { parts.append("App details:\n" + context.joined(separator: "\n")) }
        if !logs.isEmpty { parts.append("Recent activity:\n" + logs.joined(separator: "\n")) }
        if diagnostic != nil { parts.append("The system's crash or hang report is in the attached \(Self.logFileName).") }
        return parts.joined(separator: "\n\n")
    }

    /// An email to the developer. Mail links can't carry attachments, so the activity is in the body;
    /// the share and mail sheets attach the log file instead when they can.
    public func mailURL(body: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AboutText.contactEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "ByteCache bug: \(issueTitle)"),
            URLQueryItem(name: "body", value: String((body ?? plainText).prefix(6_000))),
        ]
        return components.url!
    }

    private func link(logs: String) -> URL {
        var components = URLComponents(string: "https://github.com/\(Self.repository)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "title", value: issueTitle),
            URLQueryItem(name: "what", value: whatHappened),
            URLQueryItem(name: "steps", value: steps),
            URLQueryItem(name: "platform", value: device.platform),
            URLQueryItem(name: "versions", value: versions),
            URLQueryItem(name: "logs", value: logs),
        ]
        // URLComponents leaves "&" and "+" alone inside values; encode them so they survive.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}
