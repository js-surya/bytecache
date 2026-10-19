import XCTest
import ByteCatchCore
import ByteCatchTestSupport
@testable import ByteCatchFeatures

/// CP-10: sorting not working as expected.
@MainActor
final class SortingTests: XCTestCase {
    private func model(_ replies: [StubTransport.Reply], defaults: UserDefaults? = nil) async -> SnippetListModel {
        let (session, _) = await TestSession.signedIn(replies)
        return SnippetListModel(session: session, cache: nil, sortDefaults: defaults)
    }

    func testAlphabeticalIgnoresCaseLikeAPersonWould() async {
        // ByteStash sorts A–Z by byte value: every capital before every lowercase letter.
        let page = TestJSON.page([
            TestJSON.snippet(1, title: "Markdown", pinned: true), TestJSON.snippet(2, title: "apple", pinned: true),
            TestJSON.snippet(3, title: "CSV Reader"), TestJSON.snippet(4, title: "Music"),
            TestJSON.snippet(5, title: "ddd"), TestJSON.snippet(6, title: "gello"),
        ])
        let list = await model([.json(page), .json(page)])
        list.sort = .alphaAsc
        await list.refresh()
        XCTAssertEqual(list.snippets.map(\.title), ["apple", "Markdown", "CSV Reader", "ddd", "gello", "Music"])
        list.sort = .alphaDesc
        await list.refresh()
        XCTAssertEqual(list.snippets.map(\.title), ["Markdown", "apple", "Music", "gello", "ddd", "CSV Reader"])
    }

    func testEditedSnippetMovesToItsSortedPlace() async throws {
        let page = TestJSON.page([TestJSON.snippet(1, title: "b"), TestJSON.snippet(2, title: "c"), TestJSON.snippet(3, title: "d")])
        let list = await model([.json(page), .json(page)])
        await list.refresh()
        var edited = try XCTUnwrap(list.snippets.last)
        edited.updatedAt = .now
        list.didSave(edited)
        XCTAssertEqual(list.snippets.map(\.id), [3, 1, 2], "Newest: just-edited snippet goes to the top")

        list.sort = .alphaAsc
        await list.refresh()
        var renamed = list.snippets[2]
        renamed.title = "a"
        list.didSave(renamed)
        XCTAssertEqual(list.snippets.map(\.title), ["a", "b", "c"])
    }

    func testSortChoiceIsRemembered() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = await model([], defaults: defaults)
        first.sort = .alphaDesc
        let second = await model([], defaults: defaults)
        XCTAssertEqual(second.sort, .alphaDesc)
    }
}
