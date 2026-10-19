import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

@MainActor
final class CloudSyncTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "bytecache.sync.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    private func signedIn(_ store: InMemoryCredentialStore) async -> SessionManager {
        let session = SessionManager(store: store, transport: StubTransport([.json(TestJSON.verify)]))
        await session.restore()
        return session
    }

    private func setup(cloud: InMemorySyncStore = InMemorySyncStore()) async throws -> (CloudSyncCoordinator, AppSettings, SessionManager, InMemorySyncStore) {
        let store = InMemoryCredentialStore(Credentials(server: try ServerURL("https://a.io"), token: "secret-token", username: "demo"))
        let session = await signedIn(store)
        let settings = AppSettings(defaults: defaults())
        return (CloudSyncCoordinator(settings: settings, session: session, cloud: cloud), settings, session, cloud)
    }

    func testPushWritesSettingsAndServersWithoutSecrets() async throws {
        let (sync, settings, _, cloud) = try await setup()
        settings.codeThemeID = "dracula"
        sync.push()
        let raw = try XCTUnwrap(cloud.data(forKey: CloudSyncCoordinator.serversKey))
        let blob = String(decoding: raw, as: UTF8.self)
        XCTAssertEqual(try ServerListPayload.decode(raw).servers.map(\.url), ["https://a.io"])
        XCTAssertFalse(blob.contains("secret-token"))
        XCTAssertFalse(blob.contains("demo"))
        let remote = try XCTUnwrap(cloud.data(forKey: CloudSyncCoordinator.settingsKey))
        XCTAssertEqual(try JSONDecoder().decode(SyncedSettings.self, from: remote).codeThemeID, "dracula")
    }

    func testPullAppliesRemoteSettingsAndServers() async throws {
        let cloud = InMemorySyncStore()
        cloud.setData(try JSONEncoder().encode(SyncedSettings(appearance: .dark, accent: .green, codeThemeID: "nord",
                                                              codeFontSize: 18, showLineNumbers: false)),
                      forKey: CloudSyncCoordinator.settingsKey)
        cloud.setData(try ServerListPayload(servers: [SyncedServer(id: UUID(), url: "https://b.io")], removed: []).encoded(),
                      forKey: CloudSyncCoordinator.serversKey)
        let (sync, settings, session, _) = try await setup(cloud: cloud)
        await sync.pull()
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(settings.accent, .green)
        XCTAssertEqual(settings.codeThemeID, "nord")
        XCTAssertEqual(settings.codeFontSize, 18)
        XCTAssertFalse(settings.showLineNumbers)
        XCTAssertEqual(session.accounts.map(\.server.base.absoluteString), ["https://a.io", "https://b.io"])
    }

    func testTurnedOffDoesNothing() async throws {
        let cloud = InMemorySyncStore()
        cloud.setData(try JSONEncoder().encode(SyncedSettings(appearance: .dark, accent: .green, codeThemeID: "nord",
                                                              codeFontSize: 18, showLineNumbers: false)),
                      forKey: CloudSyncCoordinator.settingsKey)
        let (sync, settings, _, _) = try await setup(cloud: cloud)
        settings.iCloudSyncEnabled = false
        await sync.pull()
        sync.push()
        XCTAssertEqual(settings.codeThemeID, CodeTheme.defaultID)
        XCTAssertNil(cloud.data(forKey: CloudSyncCoordinator.serversKey))
    }

    func testRemovalIsSharedAndRemoteRemovalsKept() async throws {
        let (sync, _, session, cloud) = try await setup()
        let gone = UUID()
        cloud.setData(try ServerListPayload(servers: [], removed: [gone]).encoded(), forKey: CloudSyncCoordinator.serversKey)
        let id = try XCTUnwrap(session.activeAccountID)
        await session.removeAccount(id)
        sync.push()
        let payload = try ServerListPayload.decode(XCTUnwrap(cloud.data(forKey: CloudSyncCoordinator.serversKey)))
        XCTAssertEqual(payload.removed, [gone, id])
        XCTAssertTrue(payload.servers.isEmpty)
    }

    func testLocalChangesArePushedAutomatically() async throws {
        let (sync, settings, _, cloud) = try await setup()
        await sync.start()
        settings.accent = .pink
        for _ in 0..<50 where (cloud.data(forKey: CloudSyncCoordinator.settingsKey)
            .flatMap { try? JSONDecoder().decode(SyncedSettings.self, from: $0) }?.accent != .pink) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let remote = try XCTUnwrap(cloud.data(forKey: CloudSyncCoordinator.settingsKey))
        XCTAssertEqual(try JSONDecoder().decode(SyncedSettings.self, from: remote).accent, .pink)
    }

    func testSyncAndHandoffSwitchesAreLocalAndDefaultOn() {
        let d = defaults()
        let settings = AppSettings(defaults: d)
        XCTAssertTrue(settings.iCloudSyncEnabled)
        XCTAssertTrue(settings.handoffEnabled)
        settings.handoffEnabled = false
        XCTAssertFalse(AppSettings(defaults: d).handoffEnabled)
    }
}

final class HandoffTests: XCTestCase {
    func testActivityRoundTripAndWebFallback() throws {
        let server = try ServerURL("https://x.io/bytestash")
        let info = SnippetActivity.userInfo(server: server, snippetID: 42)
        let parsed = try XCTUnwrap(SnippetActivity.parse(info))
        XCTAssertEqual(parsed.server, server)
        XCTAssertEqual(parsed.snippetID, 42)
        XCTAssertEqual(SnippetActivity.webURL(server: server, snippetID: 42).absoluteString, "https://x.io/bytestash/snippets/42")
        XCTAssertNil(SnippetActivity.parse(["nonsense": 1]))
        XCTAssertEqual(SnippetActivity.type, "app.bytecache.ByteCache.snippet")
    }
}
