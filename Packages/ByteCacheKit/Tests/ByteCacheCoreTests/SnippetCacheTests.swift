import XCTest
@testable import ByteCacheCore

@MainActor
final class SnippetCacheTests: XCTestCase {
    private let serverA = try! ServerURL("https://a.io")
    private let serverB = try! ServerURL("https://b.io")

    private func snippet(
        _ id: Int, title: String = "s", minutesAgo: Double = 0, language: String = "bash",
        pinned: Bool = false, favorite: Bool = false, recycled: Bool = false, description: String = ""
    ) -> Snippet {
        Snippet(
            id: id, title: title, description: description,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60),
            expiryDate: recycled ? Date(timeIntervalSince1970: 1_900_000_000) : nil,
            isPublic: false, isPinned: pinned, isFavorite: favorite, categories: [],
            fragments: [Fragment(id: id, fileName: "main", code: "echo \(id)", language: language, position: 0)],
            shareCount: 0
        )
    }

    func testStoreReturnsNewestFirst() throws {
        let cache = try SnippetCache(inMemory: true)
        cache.store([snippet(1, minutesAgo: 5), snippet(2, minutesAgo: 1), snippet(3, minutesAgo: 9)], server: serverA)
        XCTAssertEqual(cache.all(server: serverA, matching: SnippetQuery()).map(\.id), [2, 1, 3])
    }

    /// Storing a page again keeps one copy of each snippet, and a changed snippet is updated.
    func testStoringAgainUpdatesOnlyWhatChanged() throws {
        let cache = try SnippetCache(inMemory: true)
        cache.store([snippet(1, title: "a"), snippet(2, title: "b")], server: serverA)
        cache.store([snippet(1, title: "a"), snippet(2, title: "b2")], server: serverA)
        XCTAssertEqual(cache.all(server: serverA, matching: SnippetQuery()).map(\.title).sorted(), ["a", "b2"])
        cache.store([snippet(1, title: "a"), snippet(2, title: "b2")], server: serverA)
        XCTAssertEqual(cache.all(server: serverA, matching: SnippetQuery()).count, 2)
    }

    func testUpsertReplacesExisting() throws {
        let cache = try SnippetCache(inMemory: true)
        cache.store([snippet(1, title: "old")], server: serverA)
        cache.upsert(snippet(1, title: "new"), server: serverA)
        XCTAssertEqual(cache.all(server: serverA, matching: SnippetQuery()).map(\.title), ["new"])
        XCTAssertEqual(cache.snippet(id: 1, server: serverA)?.title, "new")
    }

    func testRemove() throws {
        let cache = try SnippetCache(inMemory: true)
        cache.store([snippet(1), snippet(2)], server: serverA)
        cache.remove(id: 1, server: serverA)
        XCTAssertEqual(cache.all(server: serverA, matching: SnippetQuery()).map(\.id), [2])
    }

    func testServersDoNotMix() throws {
        let cache = try SnippetCache(inMemory: true)
        cache.store([snippet(1)], server: serverA)
        cache.store([snippet(1, title: "other"), snippet(2)], server: serverB)
        XCTAssertEqual(cache.all(server: serverA, matching: SnippetQuery()).map(\.title), ["s"])
        XCTAssertEqual(cache.all(server: serverB, matching: SnippetQuery()).count, 2)
        XCTAssertNil(cache.snippet(id: 2, server: serverA))
    }

    func testFiltersApplyLocally() throws {
        let cache = try SnippetCache(inMemory: true)
        cache.store([
            snippet(1, title: "Curl helper", language: "bash", pinned: true),
            snippet(2, title: "json", language: "python", favorite: true, description: "parse CURL output"),
            snippet(3, title: "gone", recycled: true),
        ], server: serverA)
        func ids(_ q: SnippetQuery) -> [Int] { cache.all(server: serverA, matching: q).map(\.id).sorted() }

        XCTAssertEqual(ids(SnippetQuery()), [1, 2], "recycled hidden by default")
        XCTAssertEqual(ids(SnippetQuery(search: "curl")), [1, 2], "title or description, case-insensitive")
        XCTAssertEqual(ids(SnippetQuery(language: "python")), [2])
        XCTAssertEqual(ids(SnippetQuery(pinned: true)), [1])
        XCTAssertEqual(ids(SnippetQuery(favorites: true)), [2])
        XCTAssertEqual(ids(SnippetQuery(recycled: true)), [3])
    }

    func testKeepsAtMost500PerServer() throws {
        let cache = try SnippetCache(inMemory: true)
        cache.store((1...600).map { snippet($0, minutesAgo: Double($0)) }, server: serverA)
        let kept = cache.all(server: serverA, matching: SnippetQuery(limit: 1000))
        XCTAssertEqual(kept.count, 500)
        XCTAssertEqual(kept.first?.id, 1)
        XCTAssertEqual(kept.last?.id, 500, "oldest are dropped")
    }
}
