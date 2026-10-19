import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// CP-19: cloud-hosted assistants can't reach a server that's only on a private network.
@MainActor
final class PrivateServerTests: XCTestCase {
    func testPrivateAddressesAreRecognised() {
        for host in ["bytestash.tail1234.ts.net", "nas.local", "box.lan", "server.home.arpa", "pi.internal", "localhost",
                     "nas", "192.168.1.20", "10.0.0.5", "172.20.1.1", "100.101.102.103", "127.0.0.1", "169.254.3.4",
                     "fd7a:115c:a1e0::1", "fe80::1", "::1"] {
            XCTAssertTrue(ServerReach.isPrivate(host: host), host)
        }
        for host in ["bytestash-demo.pikapod.net", "snippets.example.com", "8.8.8.8", "172.32.0.1", "100.128.0.1",
                     "2606:4700::1111"] {
            XCTAssertFalse(ServerReach.isPrivate(host: host), host)
        }
    }

    func testCloudAssistantsAreMarked() {
        let setups = MCPSetup.clients(endpoint: URL(string: "https://x.io/mcp")!, key: nil)
        XCTAssertEqual(setups.filter(\.runsInCloud).map(\.name), ["Claude.ai", "ChatGPT and OpenAI API", "Perplexity"])
    }

    func testModelKnowsWhenTheServerIsPrivate() async throws {
        let (session, _) = await TestSession.signedIn([])
        XCTAssertFalse(MCPSettingsModel(session: session, secrets: InMemorySecretStore()).isPrivateServer, "x.io is public")
        let store = InMemoryCredentialStore(Credentials(server: try ServerURL("https://bytestash.tail1234.ts.net"), token: "t", username: "me"))
        let tailnet = SessionManager(store: store, transport: StubTransport([.json(TestJSON.verify)]))
        await tailnet.restore()
        let model = MCPSettingsModel(session: tailnet, secrets: InMemorySecretStore())
        XCTAssertTrue(model.isPrivateServer)
        XCTAssertEqual(model.clients.first?.name, "Claude Code", "assistants that can reach it come first")
        XCTAssertEqual(model.clients.suffix(3).map(\.runsInCloud), [true, true, true], "cloud ones last")
    }
}
