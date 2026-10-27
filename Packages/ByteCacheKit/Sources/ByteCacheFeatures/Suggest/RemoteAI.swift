import Foundation
import ByteCacheCore

public enum RemoteAIError: LocalizedError, Equatable {
    case missingKey(AIProvider)
    case missingModel
    case badServerAddress
    case keyRejected(AIProvider)
    case rateLimited(AIProvider)
    case http(status: Int, message: String?)
    case timedOut(AIProvider)
    case offline
    case emptyAnswer
    case blocked
    case unreadableAnswer

    public var errorDescription: String? {
        switch self {
        case .missingKey(let provider): "Add your \(provider.name) API key in Settings → Smart Suggestions."
        case .missingModel: "Choose a model in Settings → Smart Suggestions."
        case .badServerAddress: "Check the server address in Settings → Smart Suggestions."
        case .keyRejected(let provider): "\(provider.name) didn't accept the API key. Check it in Settings → Smart Suggestions."
        case .rateLimited(let provider): "\(provider.name) is limiting requests, or the account is out of credit. Try again later."
        case .http(let status, let message):
            "The provider returned HTTP \(status)" + (message.map { ": \($0)" } ?? ".")
        case .timedOut(let provider): "\(provider.name) took too long to answer. Try again, or pick a faster model."
        case .offline: "Couldn't reach the provider. Check your connection."
        case .emptyAnswer: "The model didn't answer. Try again or pick another model."
        case .blocked: "The provider's content filter stopped the answer."
        case .unreadableAnswer: "The model's answer couldn't be read. Try again or pick another model."
        }
    }
}

/// Talks to a provider's HTTP API with the person's own key. OpenAI, OpenRouter and local servers share
/// OpenAI's chat-completions format; Anthropic and Gemini have their own.
public struct RemoteAIClient: Sendable {
    public let provider: AIProvider
    public let model: String
    /// Only used by `.localServer`.
    public let serverAddress: String
    private let keys: any AIKeyStore
    private let transport: any HTTPTransport

    public init(provider: AIProvider, model: String, serverAddress: String = AIProvider.defaultLocalServer,
                keys: any AIKeyStore, transport: any HTTPTransport = URLSession.shared) {
        self.provider = provider
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.serverAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keys = keys
        self.transport = transport
    }

    // MARK: Requests

    /// One answer to one question.
    /// No token limit except Anthropic's required one, set high: a low cap cuts answers off, and reasoning
    /// models can spend all of it thinking and answer nothing. Length is asked for in the instructions.
    public func complete(system: String, prompt: String, maxTokens: Int = 8_192) async throws -> String {
        guard !model.isEmpty else { throw RemoteAIError.missingModel }
        let key = try apiKey()
        var request: URLRequest
        let body: [String: Any]
        switch provider {
        case .appleIntelligence:
            preconditionFailure("Apple Intelligence runs on device")
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            body = ["model": model, "max_tokens": maxTokens, "system": system,
                    "messages": [["role": "user", "content": prompt]]]
        case .gemini:
            let name = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
            guard let path = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(path):generateContent")
            else { throw RemoteAIError.missingModel }
            request = URLRequest(url: url)
            // Gemma models on this API reject system instructions, so theirs go with the prompt.
            if name.lowercased().hasPrefix("gemini") {
                body = ["systemInstruction": ["parts": [["text": system]]],
                        "contents": [["role": "user", "parts": [["text": prompt]]]]]
            } else {
                body = ["contents": [["role": "user", "parts": [["text": system + "\n\n" + prompt]]]]]
            }
        case .openAI, .openRouter, .localServer:
            request = URLRequest(url: try base().appending(path: "chat/completions"))
            // No max_tokens or temperature: newer OpenAI models reject both.
            body = ["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]]]
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        authorize(&request, key: key)
        let json = try await send(request)
        let text = Self.answer(in: json, provider: provider)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw Self.wasFiltered(json) ? RemoteAIError.blocked : RemoteAIError.emptyAnswer }
        return text
    }

    /// The provider's model ids, sorted. Also how Settings checks a key works.
    public func models() async throws -> [String] {
        let key = try apiKey()
        let url: URL = switch provider {
        case .appleIntelligence: preconditionFailure("Apple Intelligence runs on device")
        case .openAI: URL(string: "https://api.openai.com/v1/models")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/models?limit=1000")!
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")!
        case .openRouter: URL(string: "https://openrouter.ai/api/v1/models")!
        case .localServer: try base().appending(path: "models")
        }
        var request = URLRequest(url: url)
        authorize(&request, key: key)
        return Self.modelIDs(in: try await send(request), provider: provider)
    }

    private func apiKey() throws -> String? {
        let key = keys.key(for: provider)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.needsKey, key?.isEmpty ?? true { throw RemoteAIError.missingKey(provider) }
        return key?.isEmpty == false ? key : nil
    }

    private func base() throws -> URL {
        let address = provider == .localServer ? serverAddress
            : provider == .openRouter ? "https://openrouter.ai/api/v1" : "https://api.openai.com/v1"
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil
        else { throw RemoteAIError.badServerAddress }
        return url
    }

    private func authorize(_ request: inout URLRequest, key: String?) {
        request.timeoutInterval = provider.timeout
        guard let key else { return }
        switch provider {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        default:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if provider == .openRouter {
            // OpenRouter's optional app attribution.
            request.setValue("https://github.com/js-surya/bytecache", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("ByteCache", forHTTPHeaderField: "X-Title")
        }
    }

    private func send(_ request: URLRequest) async throws -> Any {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError {
            AppLog.shared.record("ai", "\(provider.rawValue) request failed: \(error.code.rawValue)")
            throw error.code == .timedOut ? RemoteAIError.timedOut(provider) : RemoteAIError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data)
        guard (200..<300).contains(status) else {
            AppLog.shared.record("ai", "\(provider.rawValue) returned HTTP \(status)")
            switch status {
            case 401, 403: throw RemoteAIError.keyRejected(provider)
            case 429: throw RemoteAIError.rateLimited(provider)
            default: throw RemoteAIError.http(status: status, message: Self.errorMessage(in: json))
            }
        }
        guard let json else { throw RemoteAIError.unreadableAnswer }
        return json
    }

    // MARK: Parsing

    static func answer(in json: Any, provider: AIProvider) -> String? {
        let root = json as? [String: Any]
        switch provider {
        case .anthropic:
            let blocks = root?["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        case .gemini:
            let candidate = (root?["candidates"] as? [[String: Any]])?.first
            let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            // Thinking models also return their reasoning, marked `thought`.
            return parts.compactMap { $0["thought"] as? Bool == true ? nil : $0["text"] as? String }.joined()
        default:
            let choice = (root?["choices"] as? [[String: Any]])?.first
            return (choice?["message"] as? [String: Any])?["content"] as? String
        }
    }

    static func wasFiltered(_ json: Any) -> Bool {
        let root = json as? [String: Any]
        let reason = ((root?["candidates"] as? [[String: Any]])?.first?["finishReason"]
            ?? (root?["choices"] as? [[String: Any]])?.first?["finish_reason"]
            ?? root?["stop_reason"]) as? String
        return ["SAFETY", "PROHIBITED_CONTENT", "content_filter", "refusal"].contains(reason ?? "")
    }

    static func modelIDs(in json: Any, provider: AIProvider) -> [String] {
        let root = json as? [String: Any]
        let ids: [String]
        if provider == .gemini {
            ids = (root?["models"] as? [[String: Any]] ?? []).compactMap { model in
                let methods = model["supportedGenerationMethods"] as? [String] ?? ["generateContent"]
                guard methods.contains("generateContent"), let name = model["name"] as? String else { return nil }
                return name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
            }
        } else {
            ids = (root?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        }
        return Array(Set(ids)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// All three formats put the reason in `error.message`.
    static func errorMessage(in json: Any?) -> String? {
        let error = (json as? [String: Any])?["error"]
        let message = (error as? [String: Any])?["message"] as? String ?? error as? String
        return message.map { String($0.prefix(200)) }
    }
}

/// Suggestions from the person's own provider.
public struct RemoteSuggester: SnippetSuggester {
    let client: RemoteAIClient

    public init(client: RemoteAIClient) { self.client = client }

    public var runsOnDevice: Bool { false }

    public func suggest(code: String, language: String, knownCategories: [String]) async throws -> SnippetSuggestion {
        let system = AIPrompts.suggestInstructions(knownCategories: knownCategories) + """

        Reply with only a JSON object, no Markdown: {"title": "…", "description": "…", "categories": ["…"]}. \
        The title has at most 6 words, no quotes or trailing period. The description is one sentence saying \
        what the code does. Categories: up to 3 lowercase one-word categories such as networking, git, docker, regex.
        """
        let answer = try await client.complete(system: system, prompt: AIPrompts.suggestPrompt(code: code, language: language))
        guard let suggestion = Self.parse(answer) else { throw RemoteAIError.unreadableAnswer }
        return suggestion
    }

    /// Reads the JSON object, tolerating Markdown fences or words around it.
    static func parse(_ answer: String) -> SnippetSuggestion? {
        guard let start = answer.firstIndex(of: "{"), let end = answer.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(answer[start...end].utf8)) as? [String: Any],
              let title = object["title"] as? String
        else { return nil }
        let description = object["description"] as? String ?? object["summary"] as? String ?? ""
        let categories = object["categories"] as? [String] ?? []
        return SnippetSuggestion(title: title, description: description, categories: categories)
    }
}

/// Explanations from the person's own provider.
public struct RemoteExplainer: SnippetExplainer {
    let client: RemoteAIClient

    public init(client: RemoteAIClient) { self.client = client }

    public func explain(code: String, language: String, title: String) async throws -> String {
        try await client.complete(system: AIPrompts.explainInstructions,
                                  prompt: AIPrompts.explainPrompt(code: code, language: language, title: title))
    }
}

/// The same instructions for Apple Intelligence and the person's own provider.
enum AIPrompts {
    static func suggestInstructions(knownCategories: [String]) -> String {
        let known = knownCategories.prefix(40).joined(separator: ", ")
        return """
        You label code snippets for a developer's snippet library. Be concise and specific to what the code does.
        \(known.isEmpty ? "" : "Prefer these existing categories when they fit: \(known).")
        """
    }

    static func suggestPrompt(code: String, language: String) -> String {
        "Language: \(language)\nCode:\n\(String(code.prefix(4000)))"
    }

    static let explainInstructions = """
    Explain code snippets to a developer in plain language. Start with one sentence on what it does, \
    then a short bullet list of the key steps or flags. Mention anything risky (deleting data, sudo, \
    network calls, secrets). Use Markdown. Keep it under 150 words.
    """

    static func explainPrompt(code: String, language: String, title: String) -> String {
        "Title: \(title)\nLanguage: \(language)\nCode:\n\(code)"
    }
}
