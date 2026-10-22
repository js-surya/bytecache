import Foundation
import Security

/// Stores all saved servers as one generic-password Keychain item, shared with the extensions through `accessGroup`.
public struct KeychainCredentialStore: CredentialStore {
    public struct KeychainError: Error, Equatable {
        public let status: OSStatus
    }

    private let accessGroup: String?
    private let service: String
    private let account = "default"

    public init(accessGroup: String?, service: String = "me.suryajs.bytecache.credentials") {
        self.accessGroup = accessGroup
        self.service = service
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
            // Access groups need the data-protection keychain on macOS; it is the only keychain on iOS.
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    public func loadAll() -> AccountList {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return AccountList() }
        return (try? AccountList.decode(data)) ?? AccountList()
    }

    public func saveAll(_ list: AccountList) throws {
        guard !list.accounts.isEmpty else { return try deleteItem() }
        let data = try JSONEncoder().encode(list)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func deleteItem() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
