import XCTest
@testable import ByteCacheFeatures
import ByteCacheCore

/// Records requests and answers each with a canned response.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    let status: Int
    let body: String

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = body
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _requests.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private func json(_ request: URLRequest?) -> [String: Any] {
    (request?.httpBody).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
}

/// CP-93: bring your own key.
final class RemoteAIClientTests: XCTestCase {
    private func client(_ provider: AIProvider, model: String = "m", key: String? = "sk-test",
                        server: String = AIProvider.defaultLocalServer, transport: RecordingTransport) -> RemoteAIClient {
        RemoteAIClient(provider: provider, model: model, serverAddress: server,
                       keys: MemoryAIKeyStore(key.map { [provider: $0] } ?? [:]), transport: transport)
    }

    func testOpenAIUsesChatCompletionsWithBearerKey() async throws {
        let transport = RecordingTransport(body: #"{"choices":[{"message":{"content":" Hello "}}]}"#)
        let answer = try await client(.openAI, model: "gpt-5-mini", transport: transport).complete(system: "S", prompt: "P")
        XCTAssertEqual(answer, "Hello")
        let request = transport.requests.first
        XCTAssertEqual(request?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let body = json(request)
        XCTAssertEqual(body["model"] as? String, "gpt-5-mini")
        XCTAssertNil(body["max_tokens"], "newer OpenAI models reject max_tokens")
        XCTAssertNil(body["temperature"])
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.map { $0["role"] ?? "" }, ["system", "user"])
        XCTAssertEqual(messages?.map { $0["content"] ?? "" }, ["S", "P"])
    }

    func testAnthropicUsesMessagesWithItsHeaders() async throws {
        let transport = RecordingTransport(body: #"{"content":[{"type":"thinking","thinking":"…"},{"type":"text","text":"Hi"},{"type":"text","text":" there"}]}"#)
        let answer = try await client(.anthropic, transport: transport).complete(system: "S", prompt: "P")
        XCTAssertEqual(answer, "Hi there")
        let request = transport.requests.first
        XCTAssertEqual(request?.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        let body = json(request)
        XCTAssertEqual(body["system"] as? String, "S")
        XCTAssertEqual(body["max_tokens"] as? Int, 8_192)
    }

    func testGeminiPutsModelInPathAndSkipsThoughts() async throws {
        let transport = RecordingTransport(body: #"{"candidates":[{"content":{"parts":[{"text":"plan","thought":true},{"text":"Answer"}]}}]}"#)
        let answer = try await client(.gemini, model: "models/gemini-2.5-flash", transport: transport).complete(system: "S", prompt: "P")
        XCTAssertEqual(answer, "Answer")
        let request = transport.requests.first
        XCTAssertEqual(request?.url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-goog-api-key"), "sk-test")
        XCTAssertFalse(request?.url?.absoluteString.contains("sk-test") ?? true, "the key stays out of the URL")
        XCTAssertNotNil(json(request)["systemInstruction"])
    }

    func testGemmaGetsInstructionsInThePrompt() async throws {
        let transport = RecordingTransport(body: #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#)
        _ = try await client(.gemini, model: "gemma-3-27b-it", transport: transport).complete(system: "S", prompt: "P")
        let body = json(transport.requests.first)
        XCTAssertNil(body["systemInstruction"])
        let parts = ((body["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: String]])
        XCTAssertEqual(parts?.first?["text"], "S\n\nP")
    }

    func testOpenRouterSendsAttribution() async throws {
        let transport = RecordingTransport(body: #"{"choices":[{"message":{"content":"ok"}}]}"#)
        _ = try await client(.openRouter, transport: transport).complete(system: "S", prompt: "P")
        let request = transport.requests.first
        XCTAssertEqual(request?.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Title"), "ByteCache")
    }

    func testLocalServerWorksWithoutAKey() async throws {
        let transport = RecordingTransport(body: #"{"choices":[{"message":{"content":"ok"}}]}"#)
        _ = try await client(.localServer, key: nil, server: "http://mac.local:11434/v1/", transport: transport)
            .complete(system: "S", prompt: "P")
        let request = transport.requests.first
        XCTAssertEqual(request?.url?.absoluteString, "http://mac.local:11434/v1/chat/completions")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request?.timeoutInterval, 120)
    }

    func testBadServerAddressIsReported() async {
        let transport = RecordingTransport(body: "{}")
        await XCTAssertThrows(RemoteAIError.badServerAddress) {
            try await self.client(.localServer, key: nil, server: "mac.local:11434", transport: transport).models()
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testMissingKeyOrModelSendsNothing() async {
        let transport = RecordingTransport(body: "{}")
        await XCTAssertThrows(RemoteAIError.missingKey(.anthropic)) {
            try await self.client(.anthropic, key: nil, transport: transport).complete(system: "S", prompt: "P")
        }
        await XCTAssertThrows(RemoteAIError.missingModel) {
            try await self.client(.openAI, model: "  ", transport: transport).complete(system: "S", prompt: "P")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testHTTPErrorsBecomeMessages() async {
        let rejected = RecordingTransport(status: 401, body: #"{"error":{"message":"Incorrect API key"}}"#)
        await XCTAssertThrows(RemoteAIError.keyRejected(.openAI)) {
            try await self.client(.openAI, transport: rejected).models()
        }
        let limited = RecordingTransport(status: 429, body: "{}")
        await XCTAssertThrows(RemoteAIError.rateLimited(.gemini)) {
            try await self.client(.gemini, transport: limited).models()
        }
        let broken = RecordingTransport(status: 404, body: #"{"error":{"type":"not_found_error","message":"model: nope"}}"#)
        await XCTAssertThrows(RemoteAIError.http(status: 404, message: "model: nope")) {
            try await self.client(.anthropic, transport: broken).complete(system: "S", prompt: "P")
        }
        XCTAssertEqual(RemoteAIError.http(status: 404, message: "model: nope").errorDescription,
                       "The provider returned HTTP 404: model: nope")
    }

    func testFilteredAndEmptyAnswers() async {
        let filtered = RecordingTransport(body: #"{"candidates":[{"finishReason":"SAFETY"}]}"#)
        await XCTAssertThrows(RemoteAIError.blocked) {
            try await self.client(.gemini, transport: filtered).complete(system: "S", prompt: "P")
        }
        let empty = RecordingTransport(body: #"{"choices":[{"message":{"content":""},"finish_reason":"length"}]}"#)
        await XCTAssertThrows(RemoteAIError.emptyAnswer) {
            try await self.client(.openAI, transport: empty).complete(system: "S", prompt: "P")
        }
    }

    func testModelListsAreReadAndSorted() async throws {
        let openAI = RecordingTransport(body: #"{"data":[{"id":"gpt-5"},{"id":"gpt-4o"},{"id":"gpt-5"}]}"#)
        let ids = try await client(.openAI, transport: openAI).models()
        XCTAssertEqual(ids, ["gpt-4o", "gpt-5"])
        XCTAssertEqual(openAI.requests.first?.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertNil(openAI.requests.first?.httpBody)

        let gemini = RecordingTransport(body: """
        {"models":[{"name":"models/gemini-2.5-flash","supportedGenerationMethods":["generateContent"]},
                   {"name":"models/text-embedding-004","supportedGenerationMethods":["embedContent"]}]}
        """)
        let geminiIDs = try await client(.gemini, transport: gemini).models()
        XCTAssertEqual(geminiIDs, ["gemini-2.5-flash"])
    }
}

final class RemoteSuggesterTests: XCTestCase {
    func testParsesJSONEvenInsideMarkdown() {
        let answer = """
        Here you go:
        ```json
        {"title": "Prune Docker", "description": "Removes unused Docker data.", "categories": ["docker", "cleanup"]}
        ```
        """
        XCTAssertEqual(RemoteSuggester.parse(answer),
                       SnippetSuggestion(title: "Prune Docker", description: "Removes unused Docker data.", categories: ["docker", "cleanup"]))
        XCTAssertNil(RemoteSuggester.parse("Sorry, I can't help."))
    }

    func testSuggestSendsCodeAndKnownCategories() async throws {
        let transport = RecordingTransport(body: #"{"choices":[{"message":{"content":"{\"title\":\"T\",\"description\":\"D\",\"categories\":[\"git\"]}"}}]}"#)
        let client = RemoteAIClient(provider: .openAI, model: "m", keys: MemoryAIKeyStore([.openAI: "k"]), transport: transport)
        let suggestion = try await RemoteSuggester(client: client)
            .suggest(code: "git status", language: "bash", knownCategories: ["git", "docker"])
        XCTAssertEqual(suggestion.title, "T")
        let messages = json(transport.requests.first)["messages"] as? [[String: String]]
        XCTAssertTrue(messages?[0]["content"]?.contains("git, docker") ?? false)
        XCTAssertTrue(messages?[1]["content"]?.contains("git status") ?? false)
    }
}

@MainActor
final class AIProviderSettingsTests: XCTestCase {
    private func freshSettings(keys: MemoryAIKeyStore = MemoryAIKeyStore()) -> (AppSettings, UserDefaults) {
        let defaults = UserDefaults(suiteName: "ai-\(UUID().uuidString)")!
        return (AppSettings(defaults: defaults, aiKeys: keys), defaults)
    }

    func testAppleIntelligenceIsTheDefault() {
        let (settings, _) = freshSettings()
        XCTAssertEqual(settings.aiProvider, .appleIntelligence)
        XCTAssertNil(settings.remoteAIClient())
    }

    func testOwnProviderNeedsAKeyBeforeItSuggests() {
        let keys = MemoryAIKeyStore()
        let (settings, defaults) = freshSettings(keys: keys)
        settings.aiProvider = .anthropic
        XCTAssertNil(settings.suggester)
        XCTAssertNil(settings.explainer)
        XCTAssertFalse(settings.aiIsReady)

        settings.setAIKey("  sk-ant  ", for: .anthropic)
        XCTAssertEqual(keys.key(for: .anthropic), "sk-ant")
        XCTAssertTrue(settings.suggester is RemoteSuggester)
        XCTAssertTrue(settings.explainer is RemoteExplainer)
        XCTAssertTrue(settings.aiIsReady)
        XCTAssertEqual(settings.remoteAIClient()?.model, AIProvider.anthropic.defaultModel)

        settings.suggestionsEnabled = false
        XCTAssertNil(settings.suggester)
        settings.suggestionsEnabled = true

        // Survives a relaunch.
        let reloaded = AppSettings(defaults: defaults, aiKeys: keys)
        XCTAssertEqual(reloaded.aiProvider, .anthropic)
        XCTAssertTrue(reloaded.aiKeysSaved.contains(.anthropic))

        settings.setAIKey("", for: .anthropic)
        XCTAssertNil(keys.key(for: .anthropic))
        XCTAssertNil(settings.suggester)
    }

    func testLocalServerNeedsAModelButNoKey() {
        let (settings, _) = freshSettings()
        settings.aiProvider = .localServer
        XCTAssertNil(settings.suggester, "no model picked yet")
        settings.setAIModel(" llama3.2 ", for: .localServer)
        XCTAssertEqual(settings.remoteAIClient()?.model, "llama3.2")
        XCTAssertNotNil(settings.suggester)
    }

    func testEveryProviderButAppleAsksBeforeSendingCode() {
        for provider in AIProvider.allCases where !provider.isOnDevice {
            XCTAssertTrue(provider.consentMessage.contains("sends the code"), provider.name)
            XCTAssertTrue(provider.consentMessage.contains("Nothing is sent to ByteCache's developer"), provider.name)
        }
        XCTAssertTrue(AIProvider.appleIntelligence.consentMessage.contains("never leaves"))
    }
}

@MainActor
final class RemoteExplainTests: XCTestCase {
    func testProviderErrorsAreShownAsIs() async {
        let model = ExplainModel(explainer: StubExplainer(result: .failure(RemoteAIError.keyRejected(.openAI))), provider: .openAI)
        await model.explain(code: "x", language: "bash", title: "t")
        XCTAssertEqual(model.state, .failed("OpenAI didn't accept the API key. Check it in Settings → Smart Suggestions."))
    }

    func testOtherErrorsNameTheProvider() async {
        struct Boom: Error {}
        let model = ExplainModel(explainer: StubExplainer(result: .failure(Boom())), provider: .gemini)
        await model.explain(code: "x", language: "bash", title: "t")
        XCTAssertEqual(model.state, .failed("Google Gemini couldn't explain this snippet right now. Try again in a moment."))
    }
}

func XCTAssertThrows<E: Error & Equatable>(_ expected: E, file: StaticString = #filePath, line: UInt = #line,
                                           _ body: () async throws -> some Any) async {
    do {
        _ = try await body()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch let error as E {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("unexpected \(error)", file: file, line: line)
    }
}

/// Against a real local server: `BC_LIVE_AI_SERVER=http://localhost:11434/v1 BC_LIVE_AI_MODEL=llama3.2`.
final class LiveLocalAITests: XCTestCase {
    func testSuggestAndExplainWithALocalModel() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["BC_LIVE_AI_SERVER"], let model = env["BC_LIVE_AI_MODEL"] else {
            throw XCTSkip("set BC_LIVE_AI_SERVER and BC_LIVE_AI_MODEL")
        }
        let client = RemoteAIClient(provider: .localServer, model: model, serverAddress: server, keys: MemoryAIKeyStore())
        let models = try await client.models()
        XCTAssertTrue(models.contains { $0.hasPrefix(model) }, "\(models)")
        let suggestion = try await RemoteSuggester(client: client)
            .suggest(code: "docker system prune -af --volumes", language: "bash", knownCategories: ["docker", "git"])
        XCTAssertFalse(suggestion.title.isEmpty)
        print("live suggestion:", suggestion)
        let explanation = try await RemoteExplainer(client: client)
            .explain(code: "git reset --hard HEAD~1", language: "bash", title: "Undo commit")
        XCTAssertFalse(explanation.isEmpty)
        print("live explanation:", explanation)
    }
}
