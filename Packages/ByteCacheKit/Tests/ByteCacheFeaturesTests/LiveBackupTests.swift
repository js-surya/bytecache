import XCTest
import ByteCacheCore
@testable import ByteCacheFeatures

/// BYTECACHE_LIVE=1 only. Read-only against the public demo.
@MainActor
final class LiveBackupTests: XCTestCase {
    func testExportWholeDemoAccount() async throws {
        guard ProcessInfo.processInfo.environment["BYTECACHE_LIVE"] == "1" else { throw XCTSkip("Set BYTECACHE_LIVE=1") }
        let server = try ServerURL("https://bytestash-demo.pikapod.net")
        let login = try await APIClient(server: server, token: nil).login(username: "demo", password: "demodemo")
        let client = APIClient(server: server, token: login.token)
        let all = try await SnippetFetcher.all(client)
        let total = try await client.snippets(SnippetQuery(limit: 1)).total
        XCTAssertEqual(all.count, total)
        let zip = try SnippetBackup.zip(folder: SnippetBackup.folder(for: all), named: "Demo")
        let size = try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int ?? 0
        print("LIVE backup: \(all.count) snippets, zip \(size) bytes")
        XCTAssertGreaterThan(size, 1000)
        _ = try SnippetBackup.decode(try SnippetBackup(snippets: all, server: "demo").encoded())
    }
}
