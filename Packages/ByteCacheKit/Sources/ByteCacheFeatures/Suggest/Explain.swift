import Foundation
import Observation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

public protocol SnippetExplainer: Sendable {
    func explain(code: String, language: String, title: String) async throws -> String
}

extension SnippetSuggesters {
    /// Apple Intelligence explainer when available (iOS/macOS 26+, on device).
    public static func explainer() -> (any SnippetExplainer)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            return AppleIntelligenceExplainer()
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct AppleIntelligenceExplainer: SnippetExplainer {
    func explain(code: String, language: String, title: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
        Explain code snippets to a developer in plain language. Start with one sentence on what it does, \
        then a short bullet list of the key steps or flags. Mention anything risky (deleting data, sudo, \
        network calls, secrets). Use Markdown. Keep it under 150 words.
        """)
        let prompt = "Title: \(title)\nLanguage: \(language)\nCode:\n\(code)"
        return try await session.respond(to: prompt).content
    }
}
#endif

@MainActor @Observable
public final class ExplainModel {
    public enum State: Equatable { case idle, loading, done(String), failed(String) }

    public static let maxCharacters = 6_000
    public private(set) var state = State.idle
    private let explainer: any SnippetExplainer

    public init(explainer: any SnippetExplainer) {
        self.explainer = explainer
    }

    static func prepared(_ code: String) -> String { String(code.prefix(maxCharacters)) }

    public func explain(code: String, language: String, title: String) async {
        state = .loading
        do {
            state = .done(try await explainer.explain(code: Self.prepared(code), language: language, title: title))
        } catch {
            state = .failed("Apple Intelligence couldn't explain this snippet right now. Try again in a moment.")
        }
    }
}

/// Sheet with the explanation (rendered Markdown).
struct ExplainSheet: View {
    @State var model: ExplainModel
    let snippet: (code: String, language: String, title: String)
    /// Called with the explanation, to keep it as an AI Note.
    var onExplained: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            switch model.state {
            case .idle, .loading:
                ProgressView("Thinking…").frame(maxWidth: .infinity).padding(.top, 60)
            case .done(let text):
                MarkdownView(text)
                Text("Generated on this device by Apple Intelligence. It can be wrong — check before running code. Kept as an AI Note under the code.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 14)
            case .failed(let message):
                ContentUnavailableView("No Explanation", symbol: .warning, description: Text(message))
            }
        }
        .navigationTitle("Explain")
        .toolbar { Button("Done") { dismiss() } }
        .task {
            await model.explain(code: snippet.code, language: snippet.language, title: snippet.title)
            if case .done(let text) = model.state { onExplained(text) }
        }
    }
}
