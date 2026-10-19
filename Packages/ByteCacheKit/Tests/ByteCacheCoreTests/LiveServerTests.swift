import XCTest
@testable import ByteCacheCore

/// Runs only with BYTECACHE_LIVE_URL and BYTECACHE_LIVE_KEY set (never commit a key).
/// Creates one clearly labelled snippet and deletes it permanently.
@MainActor
final class LiveServerTests: XCTestCase {
    func testAPIKeySessionReadWriteRoundTrip() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["BYTECACHE_LIVE_URL"], let key = env["BYTECACHE_LIVE_KEY"] else {
            throw XCTSkip("Set BYTECACHE_LIVE_URL and BYTECACHE_LIVE_KEY to run")
        }
        let session = SessionManager(store: InMemoryCredentialStore())
        try await session.connect(url)
        try await session.loginWithAPIKey(key)
        let client = try XCTUnwrap(session.client)

        _ = try await client.metadata()
        let before = try await client.snippets(SnippetQuery(limit: 5)).total

        let draft = SnippetDraft(
            title: "ByteCache live test – safe to delete", description: "Created by ByteCache's automated test.",
            categories: ["bytecache-test"],
            fragments: [FragmentDraft(fileName: "test.swift", code: "print(\"hello\")", language: "swift")], isPublic: false
        )
        let created = try await client.create(draft)
        do {
            XCTAssertEqual(created.fragments.first?.language, "swift")
            try await client.setPinned(id: created.id, true)
            let fetched = try await client.snippet(id: created.id)
            XCTAssertTrue(fetched.isPinned)
            let during = try await client.snippets(SnippetQuery(limit: 5)).total
            XCTAssertEqual(during, before + 1)
        } catch {
            try? await client.recycle(id: created.id)
            try? await client.delete(id: created.id)
            throw error
        }
        try await client.recycle(id: created.id)
        try await client.delete(id: created.id)
        let after = try await client.snippets(SnippetQuery(limit: 5)).total
        XCTAssertEqual(after, before)
    }
}
