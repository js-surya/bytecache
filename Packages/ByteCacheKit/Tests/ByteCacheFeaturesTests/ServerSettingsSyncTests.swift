import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// CP-74: theme, line numbers and search inside code follow the web app's settings on the server.
@MainActor
final class ServerSettingsSyncTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "bytecache.serversettings.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    private func signedIn(_ replies: [StubTransport.Reply], apiKey: Bool = false) async throws -> (SessionManager, StubTransport) {
        let server = try ServerURL("https://a.io")
        let credentials = apiKey ? Credentials(server: server, apiKey: "k") : Credentials(server: server, token: "t", username: "me")
        let transport = StubTransport((apiKey ? [.json(#"{"categories":[],"languages":[]}"#)] : [.json(TestJSON.verify)]) + replies)
        let session = SessionManager(store: InMemoryCredentialStore(credentials), transport: transport)
        await session.restore()
        return (session, transport)
    }

    func testServerValuesAreApplied() async throws {
        let (session, _) = try await signedIn([.json(#"{"settings":{"theme":"dark","showLineNumbers":false,"includeCodeInSearch":true,"viewMode":"grid"},"updatedAt":"x"}"#)])
        let settings = AppSettings(defaults: defaults())
        let sync = ServerSettingsSync(settings: settings, session: session)
        await sync.pull()
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertFalse(settings.showLineNumbers)
        XCTAssertTrue(settings.searchInCode)
    }

    func testOnlyTheChangedSettingIsSent() async throws {
        let (session, transport) = try await signedIn([
            .json(#"{"settings":{"theme":"light"},"updatedAt":"x"}"#),
            .json(#"{"settings":{"theme":"light","showLineNumbers":false},"updatedAt":"y"}"#),
        ])
        let settings = AppSettings(defaults: defaults())
        let sync = ServerSettingsSync(settings: settings, session: session)
        await sync.pull()
        settings.showLineNumbers = false
        await sync.push()
        XCTAssertEqual(transport.last.httpMethod, "PATCH")
        XCTAssertEqual(transport.last.url?.path, "/api/settings")
        let body = try JSONSerialization.jsonObject(with: transport.last.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["settings"] as? [String: Bool], ["showLineNumbers": false], "only what changed")
    }

    func testNothingToSendWhenUnchanged() async throws {
        let (session, transport) = try await signedIn([.json(#"{"settings":{},"updatedAt":null}"#)])
        let sync = ServerSettingsSync(settings: AppSettings(defaults: defaults()), session: session)
        await sync.pull()
        let count = transport.requests.count
        await sync.push()
        XCTAssertEqual(transport.requests.count, count)
    }

    func testOlderServersAreLeftAlone() async throws {
        let (session, transport) = try await signedIn([.json("{}", status: 404)])
        let settings = AppSettings(defaults: defaults())
        let sync = ServerSettingsSync(settings: settings, session: session)
        await sync.pull()
        let count = transport.requests.count
        settings.showLineNumbers = false
        await sync.push()
        await sync.pull()
        XCTAssertEqual(transport.requests.count, count, "no more requests to a server without /api/settings")
    }

    func testAPIKeySignInsSkipIt() async throws {
        let (session, transport) = try await signedIn([], apiKey: true)
        let sync = ServerSettingsSync(settings: AppSettings(defaults: defaults()), session: session)
        let count = transport.requests.count
        await sync.pull()
        XCTAssertEqual(transport.requests.count, count, "the server only takes settings from a full login")
    }
}
