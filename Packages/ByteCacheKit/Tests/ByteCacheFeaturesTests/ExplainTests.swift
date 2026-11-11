import XCTest
@testable import ByteCacheFeatures

/// Answers every request with the same result.
struct StubExplainer: SnippetExplainer {
    var result: Result<String, Error>
    func explain(code: String, language: String, title: String) async throws -> String { try result.get() }
    func reply(code: String, language: String, title: String, conversation: [ChatMessage]) async throws -> String {
        try result.get()
    }
}
