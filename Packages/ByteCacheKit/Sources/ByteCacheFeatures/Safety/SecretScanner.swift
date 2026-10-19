import Foundation

public enum SecretKind: String, Sendable, CaseIterable {
    case awsAccessKey, githubToken, stripeKey, slackToken, openAIKey, googleAPIKey, jwt, privateKey, password, connectionString

    public var title: String {
        switch self {
        case .awsAccessKey: "AWS access key"
        case .githubToken: "GitHub token"
        case .stripeKey: "Stripe key"
        case .slackToken: "Slack token"
        case .openAIKey: "AI API key"
        case .googleAPIKey: "Google API key"
        case .jwt: "JSON Web Token"
        case .privateKey: "Private key"
        case .password: "Password or secret"
        case .connectionString: "Password in a connection URL"
        }
    }
}

public struct SecretFinding: Equatable, Sendable {
    public let kind: SecretKind
    public let line: Int
    /// The secret itself (the part `redact` replaces), as a range in the scanned text.
    let valueRange: NSRange
}

/// Spots credentials before they're saved. Runs entirely on device; shapes only, no network checks.
public enum SecretScanner {
    public static let placeholder = "{{SECRET}}"

    private struct Pattern: @unchecked Sendable {
        let kind: SecretKind
        let regex: NSRegularExpression
        /// Capture group holding the secret value (0 = whole match).
        let group: Int
    }

    private static func pattern(_ kind: SecretKind, _ source: String, group: Int = 0) -> Pattern {
        Pattern(kind: kind, regex: try! NSRegularExpression(pattern: source, options: [.anchorsMatchLines]), group: group)
    }

    /// Most specific first; later patterns skip anything already found.
    private static let patterns: [Pattern] = [
        pattern(.privateKey, #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#),
        pattern(.awsAccessKey, #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),
        pattern(.githubToken, #"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})\b"#),
        pattern(.stripeKey, #"\b[sr]k_(?:live|test)_[A-Za-z0-9]{20,}\b"#),
        pattern(.slackToken, #"\bxox[baprs]-[A-Za-z0-9-]{10,}"#),
        pattern(.openAIKey, #"\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{32,}"#),
        pattern(.googleAPIKey, #"\bAIza[0-9A-Za-z_-]{35}\b"#),
        pattern(.jwt, #"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{10,}"#),
        pattern(.connectionString, #"\b[a-z][a-z0-9+.-]*://[^\s:/@]+:([^\s:/@]{3,})@"#, group: 1),
        // Quoted value assigned to a secret-sounding name.
        pattern(.password, #"(?i)\b[\w-]*(?:password|passwd|pwd|secret|api[_-]?key|token)\b["']?\s*[:=]\s*(["'])([^"'\s$]{6,})\1"#, group: 2),
        // Unquoted password (e.g. .env), only when it looks like a literal, not a call or variable.
        pattern(.password, #"(?i)^\s*[\w-]*(?:password|passwd|pwd)\s*=\s*([^\s"'$()\[\]{}.]*[0-9!@#%^&*+/-][^\s"'$()\[\]{}.]*)\s*$"#, group: 1),
    ]

    public static func scan(_ text: String) -> [SecretFinding] {
        let ns = text as NSString
        var findings: [SecretFinding] = []
        var taken: [NSRange] = []
        for pattern in patterns {
            for match in pattern.regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let value = match.range(at: pattern.group)
                guard value.location != NSNotFound, value.length >= 3,
                      !taken.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                taken.append(match.range)
                let line = ns.substring(to: value.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                findings.append(SecretFinding(kind: pattern.kind, line: line, valueRange: value))
            }
        }
        return findings.sorted { $0.valueRange.location < $1.valueRange.location }
    }

    /// Replaces each secret value with `{{SECRET}}`, leaving the rest of the code untouched.
    public static func redact(_ text: String) -> String {
        let result = NSMutableString(string: text)
        for finding in scan(text).sorted(by: { $0.valueRange.location > $1.valueRange.location }) {
            result.replaceCharacters(in: finding.valueRange, with: placeholder)
        }
        return result as String
    }
}
