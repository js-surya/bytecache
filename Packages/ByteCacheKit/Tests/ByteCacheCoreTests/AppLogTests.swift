import XCTest
@testable import ByteCacheCore

/// CP-14: a small rolling log for bug reports.
final class AppLogTests: XCTestCase {
    private func log(max: Int = 5) -> AppLog {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return AppLog(directory: dir, maxEntries: max)
    }

    func testRecordsInOrderWithCategoryAndTime() {
        let log = log()
        log.record("api", "GET /api/snippets → 200")
        log.record("sync", "pushed settings")
        let entries = log.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].hasSuffix("[api] GET /api/snippets → 200"), entries[0])
        XCTAssertTrue(entries[1].contains("[sync] pushed settings"))
        XCTAssertNotNil(ISO8601DateFormatter().date(from: String(entries[0].prefix(20))), "starts with a UTC timestamp")
    }

    func testKeepsOnlyTheNewestEntriesAndSurvivesRestart() {
        let first = log(max: 3)
        for i in 1...10 { first.record("t", "entry \(i)") }
        let reopened = AppLog(directory: first.directory, maxEntries: 3)
        let kept = reopened.entries()
        XCTAssertEqual(kept.count, 3)
        XCTAssertTrue(kept[0].hasSuffix("] entry 8") && kept[1].hasSuffix("] entry 9") && kept[2].hasSuffix("] entry 10"), "\(kept)")
        reopened.clear()
        XCTAssertTrue(reopened.entries().isEmpty)
    }

    func testRequestsAreLoggedWithoutQueryOrSecrets() async throws {
        let log = log(max: 50)
        let server = try ServerURL("https://my.box.lan")
        let client = APIClient(server: server, token: "secret-token", transport: StubTransportForLog(status: 500), log: log)
        _ = try? await client.snippets(SnippetQuery(search: "private search words"))
        let text = log.entries().joined(separator: "\n")
        XCTAssertTrue(text.contains("GET /api/snippets → 500"), text)
        XCTAssertFalse(text.contains("private search words"))
        XCTAssertFalse(text.contains("secret-token"))
    }
}

/// Minimal transport so this test doesn't depend on ByteCacheTestSupport.
private struct StubTransportForLog: HTTPTransport {
    let status: Int
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                          headerFields: ["Content-Type": "application/json"])!)
    }
}
