import XCTest
@testable import ByteCacheCore

/// CP-46: search filters, relevance order and close matches.
final class SearchSyntaxTests: XCTestCase {
    func testParsesFiltersAndKeepsTheText() {
        let parsed = SearchSyntax.parse("csv lang:Python #IO reader is:pinned tag:files is:fav")
        XCTAssertEqual(parsed, SearchSyntax(text: "csv reader", language: "python", categories: ["io", "files"],
                                            pinned: true, favorite: true))
        XCTAssertTrue(parsed.hasFilters)
    }

    func testPlainTextHasNoFilters() {
        XCTAssertEqual(SearchSyntax.parse("  hello   world "), SearchSyntax(text: "hello world"))
        XCTAssertFalse(SearchSyntax.parse("hello").hasFilters)
        // A filter still being typed is neither a filter nor text yet.
        XCTAssertEqual(SearchSyntax.parse("csv lang: # is:p"), SearchSyntax(text: "csv"))
    }

    func testSuggestsFiltersLanguagesAndTags() {
        XCTAssertEqual(SearchSyntax.suggestions(for: "", languages: [], categories: []).map(\.completion),
                       ["lang:", "#", "is:pinned ", "is:favorite "])
        XCTAssertEqual(SearchSyntax.suggestions(for: "csv lang:py", languages: ["Python", "PHP", "Perl"], categories: [])
                        .map(\.completion), ["csv lang:python "])
        XCTAssertEqual(SearchSyntax.suggestions(for: "#o", languages: [], categories: ["ops", "io", "Other"])
                        .map(\.completion), ["#ops ", "#other "])
        XCTAssertEqual(SearchSyntax.suggestions(for: "is:f", languages: [], categories: []).map(\.completion),
                       ["is:favorite "])
        XCTAssertEqual(SearchSyntax.suggestions(for: "reader", languages: ["Python"], categories: []), [])
    }

    private func snippet(_ id: Int, _ title: String, description: String = "", code: String = "",
                         pinned: Bool = false) -> Snippet {
        Snippet(id: id, title: title, description: description, updatedAt: nil, expiryDate: nil, isPublic: false,
                isPinned: pinned, isFavorite: false, categories: [],
                fragments: [Fragment(id: id, fileName: "main", code: code, language: "plaintext", position: 0)],
                shareCount: 0)
    }

    func testRelevanceOrder() {
        let list = [snippet(1, "Notes", code: "csv here"), snippet(2, "Reads CSV", description: ""),
                    snippet(3, "csv"), snippet(4, "Other", description: "a csv tool"), snippet(5, "CSV tools"),
                    snippet(6, "Pinned thing", code: "csv", pinned: true)]
        XCTAssertEqual(SearchRanking.arranged(list, by: "csv").map(\.id), [6, 3, 5, 2, 4, 1])
    }

    func testCloseMatches() {
        let list = [snippet(1, "CSV Reader"), snippet(2, "Python setup"), snippet(3, "Docker compose")]
        XCTAssertEqual(SearchRanking.closeMatches(list, to: "csvrd").map(\.id), [1])
        XCTAssertEqual(SearchRanking.closeMatches(list, to: "pyhton").map(\.id), [2])
        XCTAssertEqual(SearchRanking.closeMatches(list, to: "zzz"), [])
        XCTAssertEqual(SearchRanking.editDistance("pyhton", "python"), 1)
        XCTAssertEqual(SearchRanking.editDistance("pythn", "python"), 1)
    }
}
