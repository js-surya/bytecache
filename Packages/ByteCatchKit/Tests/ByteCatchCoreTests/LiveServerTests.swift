import XCTest
@testable import ByteCatchCore

/// Runs only with BYTECATCH_LIVE_URL and BYTECATCH_LIVE_KEY set (never commit a key).
/// Creates one clearly labelled snippet and deletes it permanently.
@MainActor
final class LiveServerTests: XCTestCase {
    func testAPIKeySessionReadWriteRoundTrip() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["BYTECATCH_LIVE_URL"], let key = env["BYTECATCH_LIVE_KEY"] else {
            throw XCTSkip("Set BYTECATCH_LIVE_URL and BYTECATCH_LIVE_KEY to run")
        }
        let session = SessionManager(store: InMemoryCredentialStore())
        try await session.connect(url)
        try await session.loginWithAPIKey(key)
        let client = try XCTUnwrap(session.client)

        _ = try await client.metadata()
        let before = try await client.snippets(SnippetQuery(limit: 5)).total

        let draft = SnippetDraft(
            title: "ByteCatch live test – safe to delete", description: "Created by ByteCatch's automated test.",
            categories: ["bytecatch-test"],
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
