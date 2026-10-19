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
