import XCTest
@testable import ByteCacheCore
import ByteCacheTestSupport

/// CP-19: the ByteStash MCP endpoint for connecting AI assistants.
final class MCPClientTests: XCTestCase {
    private let initOK = #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"bytestash","version":"1.0.0"}}}"#
    private let tools = #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"list_snippets"},{"name":"get_snippet"}]}}"#

    func testEndpointKeepsTheBasePath() throws {
        XCTAssertEqual(MCPClient(server: try ServerURL("https://box.lan/bytestash/"), apiKey: "k").endpoint.absoluteString,
                       "https://box.lan/bytestash/mcp")
        XCTAssertEqual(MCPClient(server: try ServerURL("notes.example.com"), apiKey: "k").endpoint.absoluteString,
                       "https://notes.example.com/mcp")
    }

    func testReadyListsToolsAndSendsBearerKey() async throws {
        let transport = StubTransport([.json(initOK), .json(tools)])
        let status = await MCPClient(server: try ServerURL("https://x.io"), apiKey: "secret", transport: transport).check()
        XCTAssertEqual(status, .ready(tools: ["list_snippets", "get_snippet"]))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path(), "/mcp")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Accept")?.contains("text/event-stream") == true)
    }

    func testBadKeyNoMCPAndOffline() async throws {
        let server = try ServerURL("https://x.io")
        let badKey = StubTransport([.json(#"{"jsonrpc":"2.0","error":{"code":-32001,"message":"Invalid API key"},"id":null}"#, status: 401)])
        let status = await MCPClient(server: server, apiKey: "nope", transport: badKey).check()
        XCTAssertEqual(status, .badKey)
        let old = StubTransport([.response(status: 404, body: "<html>Cannot POST /mcp</html>", contentType: "text/html")])
        let none = await MCPClient(server: server, apiKey: "k", transport: old).check()
        XCTAssertEqual(none, .notSupported)
        let offline = await MCPClient(server: server, apiKey: "k", transport: StubTransport([.failure(URLError(.notConnectedToInternet))])).check()
        XCTAssertEqual(offline, .offline)
    }

    func testSecretStoreKeepsOneKeyPerAccount() {
        let store = InMemorySecretStore()
        let a = UUID(), b = UUID()
        store.setSecret("one", for: a)
        store.setSecret("two", for: b)
        XCTAssertEqual(store.secret(for: a), "one")
        store.removeSecret(for: a)
        XCTAssertNil(store.secret(for: a))
        XCTAssertEqual(store.secret(for: b), "two")
    }
}
