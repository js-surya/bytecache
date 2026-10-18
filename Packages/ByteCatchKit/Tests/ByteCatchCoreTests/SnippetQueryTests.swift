import XCTest
@testable import ByteCatchCore

final class SnippetQueryTests: XCTestCase {
    func testQueryItems() {
        let q = SnippetQuery(search: "curl", language: "bash", categories: ["Net", "ops"], favorites: true, sort: .alphaAsc)
        XCTAssertEqual(Set(q.queryItems), [
            .init(name: "search", value: "curl"),
            .init(name: "language", value: "bash"),
            .init(name: "category", value: "net,ops"),
            .init(name: "favorites", value: "true"),
            .init(name: "sort", value: "alpha-asc"),
            .init(name: "limit", value: "50"),
            .init(name: "offset", value: "0"),
        ])
    }

    func testDefaultsOmitFalseAndEmptyParams() {
        let names = Set(SnippetQuery().queryItems.map(\.name))
        XCTAssertEqual(names, ["sort", "limit", "offset"])
    }
}
