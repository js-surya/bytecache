import XCTest
@testable import ByteCacheFeatures

final class MarkdownTests: XCTestCase {
    func testBlocks() {
        let text = """
        # Title
        Some *intro* text
        continues here.

        ## Steps
        - one
        - two
          - nested
        1. first
        2) second
        - [x] done
        - [ ] todo

        > quoted
        > more

        ```swift
        let x = 1
        ```
        ---
        """
        XCTAssertEqual(MarkdownDocument.parse(text), [
            .heading(level: 1, text: "Title"),
            .paragraph("Some *intro* text continues here."),
            .heading(level: 2, text: "Steps"),
            .listItem(marker: .bullet, depth: 0, text: "one"),
            .listItem(marker: .bullet, depth: 0, text: "two"),
            .listItem(marker: .bullet, depth: 1, text: "nested"),
            .listItem(marker: .number(1), depth: 0, text: "first"),
            .listItem(marker: .number(2), depth: 0, text: "second"),
            .listItem(marker: .task(done: true), depth: 0, text: "done"),
            .listItem(marker: .task(done: false), depth: 0, text: "todo"),
            .quote("quoted more"),
            .code(language: "swift", text: "let x = 1"),
            .rule,
        ])
    }

    func testUnclosedFenceKeepsRestAsCode() {
        XCTAssertEqual(MarkdownDocument.parse("```\na\n\nb"), [.code(language: nil, text: "a\n\nb")])
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(MarkdownDocument.parse("#hashtag"), [.paragraph("#hashtag")])
    }

    func testInlineFormattingKeepsLinksAndFallsBackToPlainText() {
        let styled = MarkdownDocument.inline("See [docs](https://x.io) and `code`")
        XCTAssertEqual(String(styled.characters), "See docs and code")
        XCTAssertEqual(styled.runs.first { $0.link != nil }?.link, URL(string: "https://x.io"))
        XCTAssertEqual(String(MarkdownDocument.inline("[broken](").characters), "[broken](")
    }

    func testFragmentsDetectMarkdown() {
        XCTAssertTrue(MarkdownDocument.isMarkdown(language: "markdown"))
        XCTAssertFalse(MarkdownDocument.isMarkdown(language: "swift"))
    }
}

/// CP-73: GitHub-style tables, as ByteStash 1.5.12 shows them.
final class MarkdownTableTests: XCTestCase {
    func testParsesATableWithAlignment() {
        let blocks = MarkdownDocument.parse("""
        Intro

        | Name | Count | Note |
        |:-----|:-----:|-----:|
        | a | 1 | x \\| y |
        | **b** | 22 |
        Tail
        """)
        XCTAssertEqual(blocks, [
            .paragraph("Intro"),
            .table(header: ["Name", "Count", "Note"], alignments: [.leading, .center, .trailing],
                   rows: [["a", "1", "x | y"], ["**b**", "22", ""]]),
            .paragraph("Tail"),
        ])
    }

    func testOuterPipesAreOptional() {
        let blocks = MarkdownDocument.parse("a | b\n--- | ---\n1 | 2")
        XCTAssertEqual(blocks, [.table(header: ["a", "b"], alignments: [.leading, .leading], rows: [["1", "2"]])])
    }

    func testAPipeWithoutADividerIsJustText() {
        XCTAssertEqual(MarkdownDocument.parse("a | b\nc | d"), [.paragraph("a | b c | d")])
    }
}
