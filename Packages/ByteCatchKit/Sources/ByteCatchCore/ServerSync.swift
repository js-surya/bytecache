import Foundation

/// A saved server as shared through iCloud: identity, address and display name only. Logins
/// (tokens, API keys, user names) never leave the device.
public struct SyncedServer: Codable, Equatable, Sendable {
    public var id: UUID
    public var url: String
    public var name: String?

    public init(id: UUID, url: String, name: String? = nil) {
        self.id = id
        self.url = url
        self.name = name
    }
}

/// The server list as stored in iCloud, plus servers removed on any device.
public struct ServerListPayload: Codable, Equatable, Sendable {
    public var servers: [SyncedServer]
    public var removed: Set<UUID>

    public init(servers: [SyncedServer], removed: Set<UUID>) {
        self.servers = servers
        self.removed = removed
    }

    public init(accounts: [Credentials], removed: Set<UUID>) {
        self.init(servers: accounts.map { SyncedServer(id: $0.id, url: $0.server.base.absoluteString, name: $0.name) }, removed: removed)
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> ServerListPayload { try JSONDecoder().decode(Self.self, from: data) }
}

extension AccountList {
    /// Adds servers saved on other devices (signed out), skips addresses already here, applies
    /// address/name edits made elsewhere, and drops servers removed elsewhere. The active account only changes if it was removed.
    public func merging(_ payload: ServerListPayload) -> AccountList {
        var result = self
        result.accounts.removeAll { payload.removed.contains($0.id) }
        for remote in payload.servers where !payload.removed.contains(remote.id) {
            guard let server = try? ServerURL(remote.url) else { continue }
            // Edited on another device: take its address and name, keep this device's login.
            if let index = result.accounts.firstIndex(where: { $0.id == remote.id }) {
                if !result.accounts.contains(where: { $0.id != remote.id && $0.server == server }) {
                    result.accounts[index].server = server
                }
                result.accounts[index].name = remote.name
                continue
            }
            guard !result.accounts.contains(where: { $0.server == server }) else { continue }
            result.accounts.append(Credentials(id: remote.id, server: server, name: remote.name))
        }
        if let active = result.activeID, !result.accounts.contains(where: { $0.id == active }) {
            result.activeID = nil
        }
        return result
    }
}
