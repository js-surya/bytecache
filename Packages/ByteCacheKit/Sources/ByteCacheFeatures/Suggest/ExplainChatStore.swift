import Foundation
import Observation

/// One message in Explain's chat (CP-101).
public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    /// The raw values are what OpenAI-style and Anthropic APIs call them.
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var id: UUID
    public var role: Role
    public var text: String
    /// Who wrote an answer, such as "OpenRouter (openrouter/free)".
    public var author: String?
    public var date: Date

    public init(id: UUID = UUID(), role: Role, text: String, author: String? = nil, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.author = author
        self.date = date
    }
}

/// A snippet's chat: the explanation first, then questions and answers.
public struct ExplainChat: Codable, Equatable, Sendable {
    public var messages: [ChatMessage]
    /// The code the chat last saw.
    public var codeFingerprint: String
    public var updated: Date

    /// The snippet's code changed since the chat last saw it.
    public func isStale(for code: String) -> Bool { codeFingerprint != AINoteStore.fingerprint(code) }
}

/// Explain chats, one per snippet. Saved only on this device (unlike AI Notes, not in iCloud: chats
/// grow past what iCloud key-value storage holds) and never sent to the ByteStash server.
@MainActor @Observable
public final class ExplainChatStore {
    /// Per chat; the explanation always stays, the oldest questions and answers go first.
    public static let maxMessages = 50
    /// The newest chats are kept.
    public static let maxChats = 100

    public private(set) var chats: [String: ExplainChat] = [:]
    @ObservationIgnored private let file: URL

    public init(directory: URL) {
        file = directory.appending(path: "explain-chats.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: ExplainChat].self, from: data) {
            chats = saved
        }
    }

    public var count: Int { chats.count }

    public func chat(server: String, snippetID: Int) -> ExplainChat? { chats[AINoteStore.key(server, snippetID)] }

    /// Saves the chat as it is now, for the snippet's current `code`.
    public func save(_ messages: [ChatMessage], code: String, server: String, snippetID: Int, date: Date = Date()) {
        var kept = messages
        if kept.count > Self.maxMessages {
            kept = [kept[0]] + kept.suffix(Self.maxMessages - 1)
        }
        chats[AINoteStore.key(server, snippetID)] = ExplainChat(messages: kept, codeFingerprint: AINoteStore.fingerprint(code),
                                                                updated: date)
        let extra = chats.count - Self.maxChats
        if extra > 0 {
            for (key, _) in chats.sorted(by: { $0.value.updated < $1.value.updated }).prefix(extra) { chats[key] = nil }
        }
        persist()
    }

    public func delete(server: String, snippetID: Int) {
        chats[AINoteStore.key(server, snippetID)] = nil
        persist()
    }

    public func clearAll() {
        chats = [:]
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(chats).write(to: file, options: .atomic)
    }
}
