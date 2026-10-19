import XCTest
@testable import ByteCacheFeatures

/// BYTECACHE_LIVE=1 only: reads a public gist given in BYTECACHE_GIST.
final class LiveGistTests: XCTestCase {
    func testFetchRealGist() async throws {
        guard ProcessInfo.processInfo.environment["BYTECACHE_LIVE"] == "1" else { throw XCTSkip("Set BYTECACHE_LIVE=1") }
        let candidates = try await GistImport.fetch(ProcessInfo.processInfo.environment["BYTECACHE_GIST"] ?? "", detector: .rulesOnly)
        print("LIVE gist:", candidates.map { "\($0.title) → \($0.fragments.map { "\($0.fileName)[\($0.language)]" })" })
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertFalse(candidates[0].fragments[0].code.isEmpty)
    }
}
