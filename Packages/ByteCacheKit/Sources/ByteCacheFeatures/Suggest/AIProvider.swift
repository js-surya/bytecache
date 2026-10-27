import Foundation
import ByteCacheCore

/// Who writes Smart Suggestions and explanations: Apple Intelligence on this device (the default), or a
/// service the person picks and pays for with their own API key (CP-93). Choosing anything but Apple
/// Intelligence sends the code to that service, so the app asks first (see `consentMessage`).
public enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case appleIntelligence, openAI, anthropic, gemini, openRouter
    /// Ollama, LM Studio or any server with an OpenAI-style API, at an address the person enters.
    case localServer

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Google Gemini"
        case .openRouter: "OpenRouter"
        case .localServer: "Ollama or Local Server"
        }
    }

    /// Who receives the code, for messages ("sent to …").
    var recipient: String {
        switch self {
        case .appleIntelligence: "nobody"
        case .gemini: "Google"
        case .localServer: "the server you enter"
        default: name
        }
    }

    public var isOnDevice: Bool { self == .appleIntelligence }

    /// Local servers usually run without a key; the field is still there for ones that want one.
    public var needsKey: Bool { !isOnDevice && self != .localServer }

    /// A sensible, inexpensive starting model; the person can pick another from the provider's list.
    public var defaultModel: String {
        switch self {
        case .appleIntelligence, .localServer: ""
        case .openAI: "gpt-5-mini"
        case .anthropic: "claude-haiku-5-5"
        case .gemini: "gemini-2.5-flash"
        case .openRouter: "openrouter/auto"
        }
    }

    /// Ollama's OpenAI-style endpoint on this Mac. On iPhone and iPad the person enters their Mac's address.
    public static let defaultLocalServer = "http://localhost:11434/v1"

    /// Where to make a key.
    public var keysPage: URL? {
        switch self {
        case .appleIntelligence, .localServer: nil
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .openRouter: URL(string: "https://openrouter.ai/keys")
        }
    }

    /// Local models are slower, especially the first answer while the model loads.
    var timeout: TimeInterval { self == .localServer ? 120 : 60 }

    public var consentTitle: String {
        self == .localServer ? "Send Code to Your Server?" : "Send Code to \(name)?"
    }

    /// What choosing this provider means, shown before it's turned on.
    public var consentMessage: String {
        switch self {
        case .appleIntelligence:
            "Apple Intelligence runs on this device. Your code never leaves it."
        case .localServer:
            "When ByteCache suggests a title or explains a snippet, it sends the code, its language and title to the server you enter. Only use a server you trust. Nothing is sent to ByteCache's developer."
        default:
            "When ByteCache suggests a title or explains a snippet, it sends the code, its language and title to \(recipient) with your API key. \(recipient)'s terms and privacy policy apply, and your account may be charged for each request. Nothing is sent to ByteCache's developer."
        }
    }
}

/// Saved API keys, one per provider. Keys stay on this device: they aren't synced through iCloud.
public protocol AIKeyStore: Sendable {
    func key(for provider: AIProvider) -> String?
    func setKey(_ key: String, for provider: AIProvider)
    func removeKey(for provider: AIProvider)
}

/// Keychain storage, shared with the share extensions (which also suggest titles).
public struct KeychainAIKeyStore: AIKeyStore {
    private let accessGroup: String?

    public init(accessGroup: String? = AppEnvironment.keychainGroup) {
        self.accessGroup = accessGroup
    }

    private func item(_ provider: AIProvider) -> KeychainBlob {
        KeychainBlob(service: "me.suryajs.bytecache.ai-key", account: provider.rawValue, accessGroup: accessGroup)
    }

    public func key(for provider: AIProvider) -> String? {
        item(provider).read().flatMap { String(data: $0, encoding: .utf8) }
    }

    public func setKey(_ key: String, for provider: AIProvider) {
        item(provider).write(Data(key.utf8))
    }

    public func removeKey(for provider: AIProvider) {
        item(provider).delete()
    }
}

/// For tests and previews.
public final class MemoryAIKeyStore: AIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [AIProvider: String] = [:]

    public init(_ keys: [AIProvider: String] = [:]) { self.keys = keys }

    public func key(for provider: AIProvider) -> String? { lock.withLock { keys[provider] } }
    public func setKey(_ key: String, for provider: AIProvider) { lock.withLock { keys[provider] = key } }
    public func removeKey(for provider: AIProvider) { lock.withLock { _ = keys.removeValue(forKey: provider) } }
}
