import ByteCacheCore
import Foundation
import Observation

/// API keys and password for the signed-in account. ByteStash only allows these with a password
/// login (not with an API key).
@MainActor @Observable
public final class AccountModel {
    public private(set) var keys: [APIKeyInfo] = []
    /// A newly created key's secret — shown once, never stored.
    public private(set) var newKey: CreatedAPIKey?
    public private(set) var isLoading = false
    public private(set) var allowPasswordChanges = true
    public var error: String?

    public var currentPassword = ""
    public var newPassword = ""
    public var confirmPassword = ""
    public private(set) var passwordChanged = false

    private let session: SessionManager

    public init(session: SessionManager) {
        self.session = session
    }

    /// The login expired and the app carries on with this device's backup key (CP-91).
    public var usesBackupKey: Bool { session.isUsingBackupKey }

    public var canManage: Bool {
        guard let client = session.client else { return false }
        return client.apiKey == nil && client.token != nil
    }

    // MARK: API keys

    public func loadKeys() async {
        guard canManage, let client = session.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            keys = try await client.apiKeys()
            error = nil
        } catch {
            show(error)
        }
        if let config = try? await client.authConfig() { allowPasswordChanges = config.allowPasswordChanges }
    }

    public func createKey(name rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            error = "Give the key a name."
            return
        }
        guard let client = session.client else { return }
        do {
            let created = try await client.createAPIKey(name: name)
            newKey = created
            keys.insert(created.info, at: 0)
            error = nil
        } catch {
            show(error)
        }
    }

    public func deleteKey(_ key: APIKeyInfo) async {
        guard let client = session.client, let index = keys.firstIndex(of: key) else { return }
        keys.remove(at: index)
        do {
            try await client.deleteAPIKey(id: key.id)
        } catch {
            keys.insert(key, at: min(index, keys.count))
            show(error)
        }
    }

    public func dismissNewKey() {
        newKey = nil
    }

    // MARK: Password

    public var passwordProblem: String? {
        guard !newPassword.isEmpty, !confirmPassword.isEmpty else { return nil }
        if newPassword != confirmPassword { return "The new passwords don't match." }
        if newPassword == currentPassword { return "Choose a password different from the current one." }
        return nil
    }

    public var canChangePassword: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && passwordProblem == nil && newPassword == confirmPassword
    }

    public func changePassword() async {
        guard canChangePassword, let client = session.client else { return }
        passwordChanged = false
        do {
            try await client.changePassword(current: currentPassword, new: newPassword)
            passwordChanged = true
            error = nil
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            show(error)
        }
    }

    private func show(_ apiError: APIError) {
        switch apiError {
        case .unauthorized:
            session.handleUnauthorized()
        case .server(_, let message?), .forbidden(let message?):
            error = message
        default:
            error = ErrorText.message(for: apiError)
        }
    }
}
