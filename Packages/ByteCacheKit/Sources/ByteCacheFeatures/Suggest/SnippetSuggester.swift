import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct SnippetSuggestion: Equatable, Sendable {
    public var title: String
    public var description: String
    public var categories: [String]

    public init(title: String, description: String, categories: [String]) {
        self.title = title
        self.description = description
        self.categories = categories
    }

    /// Lowercased, trimmed, de-duplicated, at most three.
    var cleanCategories: [String] {
        var seen = Set<String>()
        return categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(3).map { $0 }
    }
}

/// Suggests a title, description and categories for a piece of code.
public protocol SnippetSuggester: Sendable {
    func suggest(code: String, language: String, knownCategories: [String]) async throws -> SnippetSuggestion
    /// On-device suggesters may run on their own when code is captured; others only when the person
    /// taps Suggest, so code isn't sent anywhere without asking (CP-93).
    var runsOnDevice: Bool { get }
}

extension SnippetSuggester {
    public var runsOnDevice: Bool { true }
}

public enum SnippetSuggesters {
    /// Apple Intelligence on-device model when available (iOS/macOS 26+, supported hardware, turned on).
    public static func onDevice() -> (any SnippetSuggester)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            return AppleIntelligenceSuggester()
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedSnippetInfo {
    @Guide(description: "A short, specific title for the snippet, at most 6 words, no quotes or trailing period")
    var title: String
    @Guide(description: "One sentence saying what the code does")
    var summary: String
    @Guide(description: "Up to 3 lowercase one-word categories such as networking, git, docker, regex")
    var categories: [String]
}

/// Runs entirely on device; nothing is sent anywhere.
@available(iOS 26.0, macOS 26.0, *)
struct AppleIntelligenceSuggester: SnippetSuggester {
    func suggest(code: String, language: String, knownCategories: [String]) async throws -> SnippetSuggestion {
        let session = LanguageModelSession(instructions: AIPrompts.suggestInstructions(knownCategories: knownCategories))
        let prompt = AIPrompts.suggestPrompt(code: code, language: language)
        let info = try await session.respond(to: prompt, generating: GeneratedSnippetInfo.self).content
        return SnippetSuggestion(title: info.title, description: info.summary, categories: info.categories)
    }
}
#endif
