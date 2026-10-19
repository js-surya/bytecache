import Foundation
import Security

/// What a ByteStash server's MCP endpoint said.
public enum MCPStatus: Error, Equatable, Sendable {
    /// Connected; the tools an assistant will see.
    case ready(tools: [String])
    /// The endpoint exists but rejected the API key.
    case badKey
    /// No MCP endpoint (older ByteStash).
    case notSupported
    case offline
    case failed(String)
}

/// Talks to ByteStash's MCP endpoint (`<server>/mcp`, Streamable HTTP, API key as Bearer token),
/// only to check that an assistant would be able to connect. The assistants talk to it directly.
public struct MCPClient: Sendable {
    public let server: ServerURL
    private let apiKey: String
    private let transport: any HTTPTransport
    private let log: AppLog

    public init(server: ServerURL, apiKey: String, transport: any HTTPTransport = URLSession.shared, log: AppLog = .shared) {
        self.server = server
        self.apiKey = apiKey
        self.transport = transport
        self.log = log
    }

    public var endpoint: URL { server.endpoint("/mcp") }

    /// `initialize`, then `tools/list`.
    public func check() async -> MCPStatus {
        let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"ByteCache","version":"1"}}}"#
        switch await call(initialize) {
        case .failure(let status):
            return status
        case .success:
            break
        }
        switch await call(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#) {
        case .failure(let status):
            return status
        case .success(let data):
            let names = (try? JSONDecoder().decode(ToolsReply.self, from: data))?.result.tools.map(\.name) ?? []
            return .ready(tools: names)
        }
    }

    private struct ToolsReply: Decodable {
        struct Result: Decodable { let tools: [Tool] }
        struct Tool: Decodable { let name: String }
        let result: Result
    }

    private func call(_ body: String) async -> Result<Data, MCPStatus> {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(body.utf8)
        do {
            let (data, response) = try await transport.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            log.record("mcp", "POST /mcp → \(status)")
            let type = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            switch status {
            case 200..<300:
                return .success(Self.jsonBody(data, contentType: type))
            case 401, 403:
                return .failure(.badKey)
            case 404, 405:
                return .failure(.notSupported)
            default:
                return .failure(type.contains("html") ? .notSupported : .failed("The server answered \(status)."))
            }
        } catch {
            log.record("mcp", "POST /mcp → offline")
            return .failure(.offline)
        }
    }

    /// Streamable HTTP may answer as server-sent events: take the JSON from the `data:` line.
    private static func jsonBody(_ data: Data, contentType: String) -> Data {
        guard contentType.contains("event-stream"), let text = String(data: data, encoding: .utf8) else { return data }
        let json = text.split(separator: "\n").first { $0.hasPrefix("data:") }.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        return Data((json ?? "").utf8)
    }
}

/// Small secrets kept per saved server (the MCP API key).
public protocol SecretStore: Sendable {
    func secret(for account: UUID) -> String?
    func setSecret(_ value: String, for account: UUID)
    func removeSecret(for account: UUID)
}

/// Keychain storage, one generic-password item per saved server.
public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "app.bytecache.mcp") {
        self.service = service
    }

    private func query(_ account: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account.uuidString]
    }

    public func secret(for account: UUID) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ value: String, for account: UUID) {
        let data = Data(value.utf8)
        if SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func removeSecret(for account: UUID) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// For tests and previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [UUID: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func secret(for account: UUID) -> String? { lock.withLock { values[account] } }
    public func setSecret(_ value: String, for account: UUID) { lock.withLock { values[account] = value } }
    public func removeSecret(for account: UUID) { _ = lock.withLock { values.removeValue(forKey: account) } }
}
