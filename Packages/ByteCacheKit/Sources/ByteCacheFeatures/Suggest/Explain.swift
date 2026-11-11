import Foundation
import Observation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

public protocol SnippetExplainer: Sendable {
    func explain(code: String, language: String, title: String) async throws -> String
    /// An answer to the last message of `conversation`, which starts with the explanation (CP-101).
    func reply(code: String, language: String, title: String, conversation: [ChatMessage]) async throws -> String
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
        let session = LanguageModelSession(instructions: AIPrompts.explainInstructions)
        return try await session.respond(to: AIPrompts.explainPrompt(code: code, language: language, title: title)).content
    }

    /// The on-device model's context is small, so each answer gets the code and the newest messages.
    func reply(code: String, language: String, title: String, conversation: [ChatMessage]) async throws -> String {
        let session = LanguageModelSession(instructions: AIPrompts.chatInstructions)
        let prompt = AIPrompts.onDeviceChatPrompt(code: code, language: language, title: title, conversation: conversation)
        return try await session.respond(to: prompt).content
    }
}
#endif

#if DEBUG
/// `-BCStubAI`: canned answers after a short wait, to see Explain's chat without an AI provider.
struct StubAIExplainer: SnippetExplainer {
    func explain(code: String, language: String, title: String) async throws -> String {
        try await Task.sleep(for: .seconds(1))
        return """
        Reads a list of items and prints each one.

        - Loops over the input line by line.
        - Skips empty lines.
        - Nothing risky: no files are changed.
        """
    }

    func reply(code: String, language: String, title: String, conversation: [ChatMessage]) async throws -> String {
        try await Task.sleep(for: .seconds(1))
        return """
        Good question. You could make it shorter like this:

        ```\(language)
        for item in items where !item.isEmpty { print(item) }
        ```

        It does the same thing (\(conversation.filter { $0.role == .user }.count) question(s) so far).
        """
    }
}
#endif

/// Explain as a chat (CP-101): the explanation first, then the person's questions and the answers.
@MainActor @Observable
public final class ExplainChatModel {
    public enum Phase: Equatable { case idle, thinking, failed(String) }

    public static let maxCharacters = 6_000
    public private(set) var messages: [ChatMessage]
    public private(set) var phase = Phase.idle
    public var draft = ""
    /// The snippet's code changed since the chat last saw it; cleared once an answer uses the new code.
    public private(set) var codeChanged: Bool
    /// Who answers (named in messages).
    public let provider: AIProvider
    /// Kept on each answer, such as "OpenRouter (openrouter/free)".
    let author: String

    /// The messages changed: save them.
    @ObservationIgnored public var onChange: ([ChatMessage]) -> Void = { _ in }
    /// A new explanation: keep it as the AI Note.
    @ObservationIgnored public var onExplained: (String) -> Void = { _ in }

    @ObservationIgnored private let explainer: any SnippetExplainer
    @ObservationIgnored private let code: String
    @ObservationIgnored private let language: String
    @ObservationIgnored private let title: String
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(explainer: any SnippetExplainer, provider: AIProvider, author: String, code: String, language: String,
                title: String, messages: [ChatMessage] = [], codeChanged: Bool = false) {
        self.explainer = explainer
        self.provider = provider
        self.author = author
        self.code = code
        self.language = language
        self.title = title
        self.messages = messages
        self.codeChanged = codeChanged
    }

    static func prepared(_ code: String) -> String { String(code.prefix(maxCharacters)) }

    public var isThinking: Bool { phase == .thinking }

    public var canSend: Bool {
        !isThinking && !messages.isEmpty && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A question went unanswered (failed or stopped): Try Again asks it again.
    public var canRetry: Bool {
        guard case .failed = phase else { return false }
        return messages.isEmpty || messages.last?.role == .user
    }

    /// Explains the snippet, unless the chat already has its explanation.
    public func start() async {
        guard messages.isEmpty, phase == .idle else { return }
        await run(explaining: true).value
    }

    @discardableResult
    public func send() -> Task<Void, Never>? {
        guard canSend else { return nil }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        messages.append(ChatMessage(role: .user, text: question))
        onChange(messages)
        return run(explaining: false)
    }

    @discardableResult
    public func retry() -> Task<Void, Never>? {
        guard canRetry else { return nil }
        return run(explaining: messages.isEmpty)
    }

    public func stop() {
        guard isThinking else { return }
        task?.cancel()
        task = nil
        phase = .failed("Stopped.")
    }

    /// Keeps the explanation, drops the questions and answers.
    public func clearFollowUps() {
        task?.cancel()
        task = nil
        messages = Array(messages.prefix(1))
        phase = .idle
        onChange(messages)
    }

    /// A new explanation, and a new chat.
    @discardableResult
    public func explainAgain() -> Task<Void, Never> {
        task?.cancel()
        messages = []
        codeChanged = false
        return run(explaining: true)
    }

    private func run(explaining: Bool) -> Task<Void, Never> {
        phase = .thinking
        let explainer = explainer, code = Self.prepared(code), language = language, title = title
        let conversation = messages
        let task = Task { [weak self] in
            let result: Result<String, Error>
            do {
                result = .success(explaining
                    ? try await explainer.explain(code: code, language: language, title: title)
                    : try await explainer.reply(code: code, language: language, title: title, conversation: conversation))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            self.finish(result, explaining: explaining)
        }
        self.task = task
        return task
    }

    private func finish(_ result: Result<String, Error>, explaining: Bool) {
        task = nil
        switch result {
        case .success(let text):
            messages.append(ChatMessage(role: .assistant, text: text, author: author))
            phase = .idle
            codeChanged = false
            onChange(messages)
            if explaining { onExplained(text) }
        case .failure(let error as RemoteAIError):
            phase = .failed(error.localizedDescription)
        case .failure:
            phase = .failed(explaining
                ? "\(provider.name) couldn't explain this snippet right now. Try again in a moment."
                : "\(provider.name) couldn't answer right now. Try again in a moment.")
        }
    }
}

/// Explain's sheet: the explanation, then a chat about the code.
struct ExplainSheet: View {
    @State var model: ExplainChatModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.messages.isEmpty {
                    emptyState
                } else {
                    conversation
                }
            }
            // Short chats start at the top; a long one opens at its newest message.
            .defaultScrollAnchor(.top, for: .alignment)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { scrollToEnd(proxy) }
            .onChange(of: model.phase) { scrollToEnd(proxy) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.messages.isEmpty { inputBar }
        }
        .navigationTitle("Explain")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { model.explainAgain() } label: { Label("Explain Again", symbol: .sparkles) }
                    Button(role: .destructive) { model.clearFollowUps() } label: { Label("Clear Chat", symbol: .trash) }
                        .disabled(model.messages.count <= 1)
                } label: {
                    Label("More", symbol: .more)
                }
                .disabled(model.isThinking || model.messages.isEmpty)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 620, minHeight: 420, idealHeight: 640)
        #endif
        .task { await model.start() }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.phase {
        case .idle, .thinking:
            ProgressView("Thinking…").frame(maxWidth: .infinity).padding(.top, 60)
        case .failed(let message):
            VStack(spacing: 12) {
                ContentUnavailableView("No Explanation", symbol: .warning, description: Text(message))
                Button("Try Again") { model.retry() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 20)
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.codeChanged {
                Label("The code changed since this chat. Your next question uses the current code.", symbol: .warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                ChatBubble(message: message)
                if index == 0 { disclaimer }
            }
            status
            Color.clear.frame(height: 1).id(Self.end)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclaimer: some View {
        Text("AI answers can be wrong — check before running code. "
             + (model.provider.isOnDevice
                ? "Apple Intelligence answers on this device."
                : "Your questions and the code go to \(model.provider.name), which answers with your API key.")
             + " The explanation is kept as an AI Note under the code; the chat stays on this device.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .thinking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Thinking…").foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .failed(let message):
            HStack(spacing: 10) {
                Label(message, symbol: .warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                if model.canRetry {
                    Button("Try Again") { model.retry() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about this code…", text: $model.draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($typing)
                .onSubmit { model.send() }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Group {
                if model.isThinking {
                    Button { model.stop() } label: { Label("Stop", symbol: .stop) }
                        .accessibilityLabel("Stop")
                } else {
                    Button { model.send() } label: { Label("Send", symbol: .send) }
                        .accessibilityLabel("Send")
                        .disabled(!model.canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .labelStyle(.iconOnly)
            .font(.title)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private static let end = "end"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(Self.end, anchor: .bottom) }
    }
}

/// A question (right, tinted) or an answer (rendered Markdown, with who wrote it).
private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        Group {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 48)
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    MarkdownView(message.text)
                        .padding(-14) // MarkdownView pads itself.
                    if let author = message.author {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contextMenu {
            Button { Pasteboard.copy(message.text) } label: { Label("Copy", symbol: .copy) }
        }
    }
}
