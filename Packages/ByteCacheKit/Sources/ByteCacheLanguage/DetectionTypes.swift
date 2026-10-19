import Foundation

public struct DetectionInput: Sendable {
    public var text: String
    public var fileName: String?
    public var sourceURL: URL?

    public init(text: String, fileName: String? = nil, sourceURL: URL? = nil) {
        self.text = text
        self.fileName = fileName
        self.sourceURL = sourceURL
    }
}

public struct LanguageGuess: Equatable, Sendable {
    public var id: String
    public var confidence: Double

    public init(id: String, confidence: Double) {
        self.id = id
        self.confidence = confidence
    }
}

public enum DetectionStage: Sendable {
    case hint, shebang, structural, classifier, abstained
}

/// A deterministic check that either names a language with certainty or passes.
public protocol RuleStage: Sendable {
    func detect(_ input: DetectionInput) -> String?
}

extension String {
    /// Non-empty lines, trimmed of trailing whitespace; at most `limit`.
    func meaningfulLines(limit: Int = 200) -> [Substring] {
        var result: [Substring] = []
        for line in split(whereSeparator: \.isNewline) where !line.allSatisfy(\.isWhitespace) {
            result.append(line)
            if result.count == limit { break }
        }
        return result
    }
}
