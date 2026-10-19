import XCTest
@testable import ByteCacheCore

final class PendingSaveQueueTests: XCTestCase {
    private func queue() -> PendingSaveQueue {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return PendingSaveQueue(directory: dir)
    }

    private let draft = SnippetDraft(title: "Offline", description: "", categories: ["x"],
                                     fragments: [FragmentDraft(fileName: "main", code: "ls", language: "bash")], isPublic: false)

    func testEnqueuePersistsInOrderPerServer() throws {
        let q = queue()
        let a = try ServerURL("https://a.io"), b = try ServerURL("https://b.io")
        try q.enqueue(draft, server: a)
        var second = draft
        second.title = "Second"
        try q.enqueue(second, server: a)
        try q.enqueue(draft, server: b)
        XCTAssertEqual(q.items(for: a).map(\.draft.title), ["Offline", "Second"])
        XCTAssertEqual(q.items(for: b).count, 1)
        XCTAssertEqual(q.count, 3)
        let reopened = PendingSaveQueue(directory: q.directory)
        XCTAssertEqual(reopened.items(for: a).first?.draft.fragments.first?.code, "ls")
        try reopened.remove(reopened.items(for: a)[0].id)
        XCTAssertEqual(reopened.items(for: a).map(\.draft.title), ["Second"])
    }
}
