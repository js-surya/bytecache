import ByteCacheCore
import Foundation
import Observation

/// How to connect one assistant to ByteStash's MCP endpoint.
public struct MCPClientSetup: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    /// Where the text goes.
    public let how: String
    public let text: String
    public let isJSON: Bool
    /// Connects from the company's servers, so it can't reach a server on a private network.
    public var runsInCloud = false
}

/// Whether a server is only reachable on a private network (home network, VPN, Tailscale).
public enum ServerReach {
    private static let privateSuffixes = [".ts.net", ".local", ".lan", ".home", ".home.arpa", ".internal", ".localdomain"]

    public static func isPrivate(host raw: String) -> Bool {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || privateSuffixes.contains(where: host.hasSuffix) { return true }
        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 {
            let b = withUnsafeBytes(of: v4.s_addr) { Array($0) }
            switch (b[0], b[1]) {
            case (10, _), (127, _): return true
            case (172, 16...31), (192, 168), (169, 254): return true
            case (100, 64...127): return true // carrier-grade NAT range, used by Tailscale
            default: return false
            }
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 {
            let b = withUnsafeBytes(of: v6) { Array($0) }
            let loopback = b.dropLast().allSatisfy { $0 == 0 } && b.last == 1
            return loopback || b[0] & 0xFE == 0xFC || (b[0] == 0xFE && b[1] & 0xC0 == 0x80) // ULA (incl. Tailscale), link-local
        }
        // A single-label name ("nas") only resolves on a local network.
        return !host.contains(".")
    }
}

/// Copy-ready setup for AI assistants, filled with the endpoint and the key (or a placeholder).
public enum MCPSetup {
    public static let keyPlaceholder = "YOUR_API_KEY"

    public static func clients(endpoint: URL, key: String?) -> [MCPClientSetup] {
        let url = endpoint.absoluteString
        let bearer = "Bearer \(key ?? keyPlaceholder)"
        func json(_ object: [String: Any]) -> String {
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
        let headers = ["Authorization": bearer]
        return [
            MCPClientSetup(name: "Claude Code", how: "Run in a terminal.",
                           text: "claude mcp add --transport http bytestash \(url) --header \"Authorization: \(bearer)\"",
                           isJSON: false),
            MCPClientSetup(name: "Claude Desktop", how: "Add to claude_desktop_config.json (Settings → Developer → Edit Config), then restart Claude.",
                           text: json(["mcpServers": ["bytestash": ["type": "http", "url": url, "headers": headers]]]),
                           isJSON: true),
            MCPClientSetup(name: "Claude.ai", how: "Settings → Connectors → Add custom connector.",
                           text: "Name: ByteStash\nURL: \(url)\nHeader: Authorization: \(bearer)",
                           isJSON: false, runsInCloud: true),
            MCPClientSetup(name: "ChatGPT and OpenAI API", how: "Add to the tools of a Responses API request. In ChatGPT, add a connector with the same URL and header.",
                           text: json(["type": "mcp", "server_label": "bytestash", "server_url": url, "headers": headers,
                                       "require_approval": "never"]),
                           isJSON: true, runsInCloud: true),
            MCPClientSetup(name: "Perplexity", how: "Settings → Connectors → Add remote MCP connector.",
                           text: "URL: \(url)\nHeader: Authorization: \(bearer)",
                           isJSON: false, runsInCloud: true),
            MCPClientSetup(name: "Cursor", how: "Add to ~/.cursor/mcp.json or .cursor/mcp.json in a project.",
                           text: json(["mcpServers": ["bytestash": ["url": url, "headers": headers]]]),
                           isJSON: true),
            MCPClientSetup(name: "VS Code", how: "Add to .vscode/mcp.json in a project (or the user MCP configuration).",
                           text: json(["servers": ["bytestash": ["type": "http", "url": url, "headers": headers]]]),
                           isJSON: true),
        ]
    }
}

/// Settings → AI Assistants (MCP): the endpoint, an API key for assistants, and a connection check.
@MainActor @Observable
public final class MCPSettingsModel {
    public private(set) var status: MCPStatus?
    public private(set) var isWorking = false
    public private(set) var savedKeyHint: String?
    /// Put the saved key into the setup texts instead of the placeholder.
    public var insertKey = false
    public var error: String?

    @ObservationIgnored private let session: SessionManager
    @ObservationIgnored private let secrets: any SecretStore

    public init(session: SessionManager, secrets: any SecretStore = KeychainSecretStore()) {
        self.session = session
        self.secrets = secrets
        savedKeyHint = Self.hint(account.flatMap(secrets.secret(for:)))
    }

    private var account: UUID? { session.activeAccountID }
    private var savedKey: String? { account.flatMap(secrets.secret(for:)) }

    public var endpoint: URL? { session.mcpClient(apiKey: "")?.endpoint }
    /// Remote assistants need HTTPS.
    public var isHTTPS: Bool { endpoint?.scheme == "https" }
    /// Creating keys needs a password login; ByteStash doesn't let API keys manage keys.
    public var canCreateKey: Bool { session.client.map { $0.apiKey == nil && $0.token != nil } ?? false }
    /// Signed in with an API key: that key also works for assistants.
    /// Not this device's backup key (CP-91): signing out revokes it.
    public var loginKey: String? { session.isUsingBackupKey ? nil : session.client?.apiKey }

    /// Only reachable on a private network, so cloud-hosted assistants can't connect.
    public var isPrivateServer: Bool { endpoint?.host().map(ServerReach.isPrivate(host:)) ?? false }

    /// Assistants that can reach the server first.
    public var clients: [MCPClientSetup] {
        guard let endpoint else { return [] }
        let all = MCPSetup.clients(endpoint: endpoint, key: insertKey ? savedKey : nil)
        return all.filter { !$0.runsInCloud } + all.filter(\.runsInCloud)
    }

    /// "ByteCache MCP 2026-10-22": always Western digits and the Gregorian calendar, whatever the
    /// device's region (a Thai calendar would say 2569).
    nonisolated static func keyName(on date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "ByteCache MCP \(formatter.string(from: date))"
    }

    /// Creates a dedicated key on the server, keeps it in the Keychain and checks the connection.
    public func createKey() async {
        guard canCreateKey, let client = session.client, let account else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let created = try await client.createAPIKey(name: Self.keyName(on: .now))
            secrets.setSecret(created.key, for: account)
            savedKeyHint = Self.hint(created.key)
            status = await session.mcpClient(apiKey: created.key)?.check()
        } catch {
            self.error = ErrorText.message(for: error)
        }
    }

    /// Uses a key made in the ByteStash web app; kept only if the server accepts it.
    public func useKey(_ raw: String) async {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let account, let client = session.mcpClient(apiKey: key) else { return }
        isWorking = true
        defer { isWorking = false }
        let result = await client.check()
        status = result
        if case .ready = result {
            secrets.setSecret(key, for: account)
            savedKeyHint = Self.hint(key)
        }
    }

    public func testConnection() async {
        guard let key = savedKey, let client = session.mcpClient(apiKey: key) else { return }
        isWorking = true
        defer { isWorking = false }
        status = await client.check()
    }

    /// Forgets the key on this device (it still exists on the server until revoked in API Keys).
    public func forgetKey() {
        guard let account else { return }
        secrets.removeSecret(for: account)
        savedKeyHint = nil
        insertKey = false
        status = nil
    }

    public func copy(_ setup: MCPClientSetup) {
        Pasteboard.copy(setup.text)
    }

    private static func hint(_ key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        return "••••" + key.suffix(4)
    }
}
