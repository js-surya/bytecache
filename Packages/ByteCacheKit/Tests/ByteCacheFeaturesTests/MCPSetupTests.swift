import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

/// CP-19: copy-ready setup for AI assistants, and the key flow.
@MainActor
final class MCPSetupTests: XCTestCase {
    private let endpoint = URL(string: "https://box.lan/bytestash/mcp")!

    func testEveryClientGetsTheEndpointAndPlaceholder() throws {
        let setups = MCPSetup.clients(endpoint: endpoint, key: nil)
        XCTAssertEqual(setups.map(\.name), ["Claude Code", "Claude Desktop", "Claude.ai", "ChatGPT and OpenAI API",
                                             "Perplexity", "Cursor", "VS Code"])
        for setup in setups {
            XCTAssertTrue(setup.text.contains(endpoint.absoluteString), setup.name)
            XCTAssertTrue(setup.text.contains(MCPSetup.keyPlaceholder), setup.name)
            if setup.isJSON {
                XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(setup.text.utf8)), "\(setup.name) is valid JSON")
            }
        }
        let code = setups[0].text
        XCTAssertEqual(code, "claude mcp add --transport http bytestash https://box.lan/bytestash/mcp --header \"Authorization: Bearer YOUR_API_KEY\"")
    }

    func testKeyIsInsertedOnlyWhenAsked() {
        let setups = MCPSetup.clients(endpoint: endpoint, key: "abc123")
        XCTAssertTrue(setups.allSatisfy { $0.text.contains("abc123") && !$0.text.contains(MCPSetup.keyPlaceholder) })
    }

    func testCreatingAKeyStoresItAndChecksTheConnection() async throws {
        let created = #"{"id":7,"name":"ByteCache MCP","key":"newsecretkey","created_at":"2026-10-19 10:00:00"}"#
        let (session, _) = await TestSession.signedIn([.json(created), .json(#"{"jsonrpc":"2.0","id":1,"result":{}}"#),
                                                       .json(#"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"list_snippets"}]}}"#)])
        let secrets = InMemorySecretStore()
        let model = MCPSettingsModel(session: session, secrets: secrets)
        XCTAssertNil(model.savedKeyHint)
        XCTAssertTrue(model.canCreateKey)
        await model.createKey()
        XCTAssertEqual(secrets.secret(for: try XCTUnwrap(session.activeAccountID)), "newsecretkey")
        XCTAssertEqual(model.savedKeyHint, "••••tkey")
        XCTAssertEqual(model.status, .ready(tools: ["list_snippets"]))
        model.insertKey = true
        XCTAssertTrue(model.clients[0].text.contains("newsecretkey"))
        model.forgetKey()
        XCTAssertNil(model.savedKeyHint)
        XCTAssertTrue(model.clients[0].text.contains(MCPSetup.keyPlaceholder))
    }

    func testPastedKeyIsKeptOnlyIfTheServerAcceptsIt() async throws {
        let (session, _) = await TestSession.signedIn([
            .json(#"{"jsonrpc":"2.0","error":{"code":-32001,"message":"Invalid API key"},"id":null}"#, status: 401),
        ])
        let secrets = InMemorySecretStore()
        let model = MCPSettingsModel(session: session, secrets: secrets)
        await model.useKey("  wrong-key \n")
        XCTAssertEqual(model.status, .badKey)
        XCTAssertNil(secrets.secret(for: try XCTUnwrap(session.activeAccountID)))
    }

    func testKeyNeverReachesTheActivityLog() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = AppLog(directory: dir)
        let transport = StubTransport([.json(#"{"jsonrpc":"2.0","id":1,"result":{}}"#), .json(#"{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}"#)])
        _ = await MCPClient(server: TestSession.server, apiKey: "supersecretvalue", transport: transport, log: log).check()
        let text = log.entries().joined()
        XCTAssertTrue(text.contains("mcp"), text)
        XCTAssertFalse(text.contains("supersecretvalue"))
    }
}
