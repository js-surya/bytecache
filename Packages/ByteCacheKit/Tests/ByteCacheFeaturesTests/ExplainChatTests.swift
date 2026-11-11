import XCTest
import ByteCacheCore
@testable import ByteCacheFeatures

private func json(_ request: URLRequest?) -> [String: Any] {
    (request?.httpBody).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
}

private func message(_ role: ChatMessage.Role, _ text: String) -> ChatMessage {
    ChatMessage(role: role, text: text)
}

/// Records what it was asked and answers from a script.
private final class ScriptedExplainer: SnippetExplainer, @unchecked Sendable {
    private let lock = NSLock()
    private var _conversations: [[ChatMessage]] = []
    private var answers: [Result<String, Error>]
    var conversations: [[ChatMessage]] { lock.withLock { _conversations } }

    init(_ answers: [Result<String, Error>]) { self.answers = answers }

    private func next() throws -> String {
        try lock.withLock { answers.isEmpty ? .success("…") : answers.removeFirst() }.get()
    }

    func explain(code: String, language: String, title: String) async throws -> String { try next() }

    func reply(code: String, language: String, title: String, conversation: [ChatMessage]) async throws -> String {
        lock.withLock { _conversations.append(conversation) }
        return try next()
    }
}

private struct Boom: Error {}

/// CP-101: chat about a snippet's code in Explain.
@MainActor
final class ExplainChatModelTests: XCTestCase {
    private func model(_ explainer: some SnippetExplainer, messages: [ChatMessage] = [],
                       provider: AIProvider = .appleIntelligence) -> ExplainChatModel {
        ExplainChatModel(explainer: explainer, provider: provider, author: "Apple Intelligence",
                         code: "ls -la", language: "bash", title: "List", messages: messages)
    }

    func testStartsWithTheExplanation() async {
        var explained: String?
        var saved: [ChatMessage] = []
        let chat = model(ScriptedExplainer([.success("Lists files.")]))
        chat.onExplained = { explained = $0 }
        chat.onChange = { saved = $0 }
        await chat.start()
        XCTAssertEqual(chat.messages.map(\.text), ["Lists files."])
        XCTAssertEqual(chat.messages.first?.role, .assistant)
        XCTAssertEqual(chat.messages.first?.author, "Apple Intelligence")
        XCTAssertEqual(explained, "Lists files.", "kept as the AI Note")
        XCTAssertEqual(saved.map(\.text), ["Lists files."])
        XCTAssertEqual(chat.phase, .idle)
    }

    func testAnExistingChatIsNotExplainedAgain() async {
        let explainer = ScriptedExplainer([.success("new")])
        let chat = model(explainer, messages: [message(.assistant, "Lists files."), message(.user, "why -a?")])
        await chat.start()
        XCTAssertEqual(chat.messages.map(\.text), ["Lists files.", "why -a?"])
    }

    func testFollowUpGetsTheWholeConversation() async {
        let explainer = ScriptedExplainer([.success("Lists files."), .success("`-a` shows hidden files.")])
        let chat = model(explainer)
        await chat.start()
        chat.draft = "  why -a?  "
        await chat.send()?.value
        XCTAssertEqual(chat.draft, "")
        XCTAssertEqual(chat.messages.map(\.text), ["Lists files.", "why -a?", "`-a` shows hidden files."])
        XCTAssertEqual(chat.messages.map(\.role), [.assistant, .user, .assistant])
        XCTAssertEqual(explainer.conversations.first?.map(\.text), ["Lists files.", "why -a?"])
    }

    func testCantSendEmptyOrWhileThinking() async {
        let chat = model(ScriptedExplainer([.success("Lists files.")]))
        await chat.start()
        chat.draft = "   "
        XCTAssertFalse(chat.canSend)
        XCTAssertNil(chat.send())
        XCTAssertEqual(chat.messages.count, 1)
    }

    func testFailedAnswerKeepsTheQuestionAndCanBeRetried() async {
        let explainer = ScriptedExplainer([.success("Lists files."), .failure(Boom()), .success("Shows hidden files.")])
        let chat = model(explainer)
        await chat.start()
        chat.draft = "why -a?"
        await chat.send()?.value
        XCTAssertEqual(chat.phase, .failed("Apple Intelligence couldn't answer right now. Try again in a moment."))
        XCTAssertEqual(chat.messages.last?.text, "why -a?")
        await chat.retry()?.value
        XCTAssertEqual(chat.phase, .idle)
        XCTAssertEqual(chat.messages.map(\.text), ["Lists files.", "why -a?", "Shows hidden files."])
    }

    func testProviderErrorsAreShownAsIs() async {
        let chat = model(ScriptedExplainer([.failure(RemoteAIError.rateLimited(.openRouter))]), provider: .openRouter)
        await chat.start()
        XCTAssertEqual(chat.phase, .failed(RemoteAIError.rateLimited(.openRouter).localizedDescription))
        XCTAssertTrue(chat.messages.isEmpty)
    }

    func testFailedExplanationNamesTheProvider() async {
        let chat = model(ScriptedExplainer([.failure(Boom())]))
        await chat.start()
        XCTAssertEqual(chat.phase, .failed("Apple Intelligence couldn't explain this snippet right now. Try again in a moment."))
    }

    func testClearChatKeepsTheExplanation() async {
        let chat = model(ScriptedExplainer([]), messages: [message(.assistant, "Lists files."), message(.user, "q"),
                                                           message(.assistant, "a")])
        var saved: [ChatMessage] = []
        chat.onChange = { saved = $0 }
        chat.clearFollowUps()
        XCTAssertEqual(chat.messages.map(\.text), ["Lists files."])
        XCTAssertEqual(saved.map(\.text), ["Lists files."])
    }

    func testExplainAgainStartsANewChat() async {
        let chat = model(ScriptedExplainer([.success("Fresh.")]),
                         messages: [message(.assistant, "Old."), message(.user, "q"), message(.assistant, "a")])
        await chat.explainAgain().value
        XCTAssertEqual(chat.messages.map(\.text), ["Fresh."])
    }

    func testStopLeavesTheQuestionToRetry() async {
        let chat = model(SlowExplainer(), messages: [message(.assistant, "Lists files.")])
        chat.draft = "why?"
        let task = chat.send()
        XCTAssertEqual(chat.phase, .thinking)
        chat.stop()
        await task?.value
        XCTAssertEqual(chat.phase, .failed("Stopped."))
        XCTAssertEqual(chat.messages.map(\.text), ["Lists files.", "why?"])
    }

    func testVeryLongCodeIsTrimmedForTheModel() {
        let long = String(repeating: "a", count: 20_000)
        XCTAssertEqual(ExplainChatModel.prepared(long).count, ExplainChatModel.maxCharacters)
    }
}

private struct SlowExplainer: SnippetExplainer {
    func explain(code: String, language: String, title: String) async throws -> String { "…" }
    func reply(code: String, language: String, title: String, conversation: [ChatMessage]) async throws -> String {
        try await Task.sleep(for: .seconds(30))
        return "late"
    }
}

@MainActor
final class ExplainChatStoreTests: XCTestCase {
    private let server = "https://a.io"

    private func directory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testKeepsAChatAcrossLaunches() {
        let dir = directory()
        let store = ExplainChatStore(directory: dir)
        store.save([message(.assistant, "Lists files."), message(.user, "why?")], code: "ls", server: server, snippetID: 3)
        let again = ExplainChatStore(directory: dir)
        XCTAssertEqual(again.chat(server: server, snippetID: 3)?.messages.map(\.text), ["Lists files.", "why?"])
        XCTAssertNil(again.chat(server: "https://b.io", snippetID: 3), "servers don't mix")
        XCTAssertEqual(again.count, 1)
    }

    func testKnowsWhenTheCodeChanged() {
        let store = ExplainChatStore(directory: directory())
        store.save([message(.assistant, "x")], code: "ls", server: server, snippetID: 3)
        let chat = store.chat(server: server, snippetID: 3)
        XCTAssertEqual(chat?.isStale(for: "ls"), false)
        XCTAssertEqual(chat?.isStale(for: "ls -la"), true)
    }

    func testKeepsTheExplanationAndTheNewestMessages() {
        let store = ExplainChatStore(directory: directory())
        let many = [message(.assistant, "explanation")] + (1...60).map { message($0 % 2 == 1 ? .user : .assistant, "m\($0)") }
        store.save(many, code: "ls", server: server, snippetID: 1)
        let kept = store.chat(server: server, snippetID: 1)?.messages ?? []
        XCTAssertEqual(kept.count, ExplainChatStore.maxMessages)
        XCTAssertEqual(kept.first?.text, "explanation")
        XCTAssertEqual(kept.last?.text, "m60")
        XCTAssertEqual(kept[1].text, "m12")
    }

    func testKeepsOnlyTheNewestChats() {
        let store = ExplainChatStore(directory: directory())
        for id in 0..<(ExplainChatStore.maxChats + 5) {
            store.save([message(.assistant, "x")], code: "ls", server: server, snippetID: id,
                       date: Date(timeIntervalSince1970: TimeInterval(id)))
        }
        XCTAssertEqual(store.count, ExplainChatStore.maxChats)
        XCTAssertNil(store.chat(server: server, snippetID: 0))
        XCTAssertNotNil(store.chat(server: server, snippetID: ExplainChatStore.maxChats + 4))
    }

    func testDeleteAndClearAll() {
        let dir = directory()
        let store = ExplainChatStore(directory: dir)
        store.save([message(.assistant, "x")], code: "ls", server: server, snippetID: 1)
        store.save([message(.assistant, "y")], code: "ls", server: server, snippetID: 2)
        store.delete(server: server, snippetID: 1)
        XCTAssertNil(store.chat(server: server, snippetID: 1))
        store.clearAll()
        XCTAssertEqual(ExplainChatStore(directory: dir).count, 0)
    }
}

/// The conversation as each provider receives it.
final class ExplainChatRequestTests: XCTestCase {
    private let conversation = [ChatMessage(role: .assistant, text: "Lists files."),
                                ChatMessage(role: .user, text: "why -a?")]

    private func explainer(_ provider: AIProvider, transport: RecordingTransport) -> RemoteExplainer {
        RemoteExplainer(client: RemoteAIClient(provider: provider, model: "m",
                                               keys: MemoryAIKeyStore([provider: "sk-test"]), transport: transport))
    }

    func testOpenAIStyleSendsTheTurnsInOrder() async throws {
        let transport = RecordingTransport(body: #"{"choices":[{"message":{"content":"Hidden files."}}]}"#)
        let answer = try await explainer(.openRouter, transport: transport)
            .reply(code: "ls -la", language: "bash", title: "List", conversation: conversation)
        XCTAssertEqual(answer, "Hidden files.")
        let messages = json(transport.requests.first)["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.map { $0["role"] ?? "" }, ["system", "user", "assistant", "user"])
        XCTAssertEqual(messages?[0]["content"], AIPrompts.chatInstructions)
        XCTAssertTrue(messages?[1]["content"]?.contains("ls -la") ?? false, "the current code comes first")
        XCTAssertEqual(messages?[2]["content"], "Lists files.")
        XCTAssertEqual(messages?[3]["content"], "why -a?")
    }

    func testAnthropicSendsUserAndAssistantTurns() async throws {
        let transport = RecordingTransport(body: #"{"content":[{"type":"text","text":"ok"}]}"#)
        _ = try await explainer(.anthropic, transport: transport)
            .reply(code: "ls", language: "bash", title: "t", conversation: conversation)
        let body = json(transport.requests.first)
        XCTAssertEqual(body["system"] as? String, AIPrompts.chatInstructions)
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.map { $0["role"] as? String ?? "" }, ["user", "assistant", "user"])
    }

    func testGeminiCallsTheAssistantModel() async throws {
        let transport = RecordingTransport(body: #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#)
        _ = try await explainer(.gemini, transport: transport)
            .reply(code: "ls", language: "bash", title: "t", conversation: conversation)
        let contents = json(transport.requests.first)["contents"] as? [[String: Any]]
        XCTAssertEqual(contents?.map { $0["role"] as? String ?? "" }, ["user", "model", "user"])
    }

    func testRepeatedQuestionsAreJoinedIntoOneTurn() {
        let turns = AIPrompts.chatTurns(code: "ls", language: "bash", title: "t",
                                        conversation: conversation + [ChatMessage(role: .user, text: "and -l?")])
        XCTAssertEqual(turns.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(turns.last?.text, "why -a?\n\nand -l?")
    }

    func testOnDevicePromptKeepsTheCodeAndTheNewestMessages() {
        let long = (1...40).map { ChatMessage(role: $0 % 2 == 1 ? .user : .assistant,
                                               text: "message \($0) " + String(repeating: "x", count: 300)) }
        let prompt = AIPrompts.onDeviceChatPrompt(code: "ls -la", language: "bash", title: "List", conversation: long)
        XCTAssertTrue(prompt.contains("ls -la"))
        XCTAssertTrue(prompt.contains("message 40"), "the newest question is always there")
        XCTAssertFalse(prompt.contains("message 1 "), "the oldest drop out")
        XCTAssertLessThan(prompt.count, AIPrompts.onDeviceBudget + 400)
    }
}
