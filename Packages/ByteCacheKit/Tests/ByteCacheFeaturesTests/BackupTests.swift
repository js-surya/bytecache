import XCTest
import ByteCacheCore
import ByteCacheTestSupport
@testable import ByteCacheFeatures

final class BackupFormatTests: XCTestCase {
    private func snippet(_ id: Int, _ title: String, _ files: [(String, String, String)], pinned: Bool = false) -> Snippet {
        Snippet(id: id, title: title, description: "d", updatedAt: nil, expiryDate: nil, isPublic: false, isPinned: pinned,
                isFavorite: false, categories: ["ops"],
                fragments: files.enumerated().map { Fragment(id: $0, fileName: $1.0, code: $1.1, language: $1.2, position: $0) },
                shareCount: 0)
    }

    func testJSONRoundTrip() throws {
        let data = try SnippetBackup(snippets: [snippet(1, "Cleanup", [("main", "docker prune", "bash")], pinned: true)],
                                     server: "x.io").encoded()
        let decoded = try SnippetBackup.decode(data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.snippets.first?.title, "Cleanup")
        XCTAssertEqual(decoded.snippets.first?.isPinned, true)
        XCTAssertEqual(decoded.snippets.first?.fragments.first?.code, "docker prune")
        XCTAssertThrowsError(try SnippetBackup.decode(Data("{}".utf8)))
    }

    func testFolderLayoutUsesSaveNamesAndKeepsThemUnique() throws {
        let snippets = [snippet(1, "Cleanup", [("main", "a", "bash")]), snippet(2, "Cleanup", [("main", "b", "bash")]),
                        snippet(3, "Web", [("index", "<p>", "html"), ("style", "p{}", "css")])]
        let root = SnippetBackup.folder(for: snippets)
        let names = Set(root.fileWrappers?.keys.map { $0 } ?? [])
        XCTAssertEqual(names, ["Cleanup.sh", "Cleanup 2.sh", "Web"])
        XCTAssertEqual(Set(root.fileWrappers?["Web"]?.fileWrappers?.keys.map { $0 } ?? []), ["index.html", "style.css"])
    }

    func testZipContainsEveryFile() throws {
        let zip = try SnippetBackup.zip(folder: SnippetBackup.folder(for: [snippet(1, "Web", [("index", "<p>", "html"), ("style", "p{}", "css")])]),
                                        named: "ByteCache Backup")
        let data = try Data(contentsOf: zip)
        XCTAssertEqual(data.prefix(2), Data("PK".utf8))
        let listing = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(listing.contains("Web/index.html"))
        XCTAssertTrue(listing.contains("Web/style.css"))
    }
}

@MainActor
final class BackupImportTests: XCTestCase {
    func testImportCreatesMissingSnippetsAndSkipsDuplicates() async throws {
        let existing = TestJSON.page([TestJSON.snippet(1, title: "Cleanup", code: "docker prune")])
        let backup = SnippetBackup(snippets: [], server: "x").with([
            .init(title: "Cleanup", description: "", categories: [], isPublic: false, isPinned: false, isFavorite: false,
                  fragments: [.init(fileName: "main", code: "docker prune", language: "bash")]),
            .init(title: "New one", description: "", categories: ["git"], isPublic: false, isPinned: true, isFavorite: false,
                  fragments: [.init(fileName: "main", code: "git log", language: "bash")]),
        ])
        let (session, transport) = await TestSession.signedIn([.json(existing), .json(TestJSON.snippet(7, title: "New one"), status: 201), .json("{}")])
        let result = try await BackupImporter(session: session).importBackup(backup)
        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(result.skipped, 1)
        let posts = transport.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.count, 1)
        XCTAssertTrue(transport.requests.contains { $0.url?.path == "/api/snippets/7/pin" })
    }
}
