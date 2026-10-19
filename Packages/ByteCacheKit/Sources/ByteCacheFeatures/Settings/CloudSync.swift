import ByteCacheCore
import Foundation
import Observation

/// Small key-value storage shared across the user's devices.
@MainActor
public protocol KeyValueSyncStore: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data, forKey key: String)
    func synchronize()
    /// Posted when another device changed a value; nil when the store never changes remotely.
    var externalChangeNotification: Notification.Name? { get }
}

/// iCloud key-value storage. Works only in builds signed with the iCloud capability; otherwise
/// values simply stay local.
@MainActor
public final class UbiquitousSyncStore: KeyValueSyncStore {
    private let store = NSUbiquitousKeyValueStore.default
    public init() {}
    public func data(forKey key: String) -> Data? { store.data(forKey: key) }
    public func setData(_ data: Data, forKey key: String) { store.set(data, forKey: key) }
    public func synchronize() { store.synchronize() }
    public var externalChangeNotification: Notification.Name? { NSUbiquitousKeyValueStore.didChangeExternallyNotification }

    /// Whether this device is signed in to iCloud.
    public static var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }
}

/// For tests and previews.
@MainActor
public final class InMemorySyncStore: KeyValueSyncStore {
    private var values: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { values[key] }
    public func setData(_ data: Data, forKey key: String) { values[key] = data }
    public func synchronize() {}
    public var externalChangeNotification: Notification.Name? { nil }
}

/// Keeps display settings and the server list in step across devices through iCloud.
/// Logins never sync: other devices get each server signed out.
@MainActor @Observable
public final class CloudSyncCoordinator {
    public static let settingsKey = "settings.v1"
    public static let serversKey = "servers.v1"

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let session: SessionManager
    @ObservationIgnored private let cloud: any KeyValueSyncStore
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var started = false

    public init(settings: AppSettings, session: SessionManager, cloud: any KeyValueSyncStore) {
        self.settings = settings
        self.session = session
        self.cloud = cloud
    }

    private var enabled: Bool { settings.iCloudSyncEnabled }

    /// Pull what other devices saved, publish ours, then follow changes both ways.
    public func start() async {
        guard !started else { return }
        started = true
        if let name = cloud.externalChangeNotification {
            observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.pull() }
            }
        }
        cloud.synchronize()
        await pull()
        push()
        observeLocalChanges()
    }

    /// Call when the switch is turned on, so this device catches up straight away.
    public func syncNow() async {
        cloud.synchronize()
        await pull()
        push()
    }

    public func pull() async {
        guard enabled else { return }
        if let data = cloud.data(forKey: Self.settingsKey),
           let remote = try? JSONDecoder().decode(SyncedSettings.self, from: data), remote != settings.synced {
            settings.apply(remote)
        }
        if let data = cloud.data(forKey: Self.serversKey), let payload = try? ServerListPayload.decode(data) {
            await session.applySyncedServers(payload)
        }
    }

    public func push() {
        guard enabled else { return }
        if let data = try? JSONEncoder().encode(settings.synced), data != cloud.data(forKey: Self.settingsKey) {
            cloud.setData(data, forKey: Self.settingsKey)
        }
        let remoteRemoved = cloud.data(forKey: Self.serversKey).flatMap { try? ServerListPayload.decode($0) }?.removed ?? []
        let payload = ServerListPayload(accounts: session.accounts, removed: remoteRemoved.union(session.removedAccountIDs))
        if let data = try? payload.encoded(), data != cloud.data(forKey: Self.serversKey) {
            cloud.setData(data, forKey: Self.serversKey)
        }
    }

    private func observeLocalChanges() {
        withObservationTracking {
            _ = settings.synced
            _ = settings.iCloudSyncEnabled
            _ = session.accounts
            _ = session.removedAccountIDs
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.push()
                self.observeLocalChanges()
            }
        }
    }
}
