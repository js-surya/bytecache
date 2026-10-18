import XCTest
import UniformTypeIdentifiers
@testable import ByteCatchFeatures

final class SharedItemLoaderTests: XCTestCase {
    private func item(_ providers: [NSItemProvider], title: String? = nil, content: String? = nil) -> NSExtensionItem {
        let item = NSExtensionItem()
        item.attachments = providers
        item.attributedTitle = title.map { NSAttributedString(string: $0) }
        item.attributedContentText = content.map { NSAttributedString(string: $0) }
        return item
    }

    private func textProvider(_ text: String) -> NSItemProvider {
        NSItemProvider(item: text as NSString, typeIdentifier: UTType.plainText.identifier)
    }

    private func urlProvider(_ url: URL) -> NSItemProvider {
        NSItemProvider(item: url as NSURL, typeIdentifier: url.isFileURL ? UTType.fileURL.identifier : UTType.url.identifier)
    }

    private func tempFile(_ name: String, contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
        try contents.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testPlainText() async {
        let result = await SharedItemLoader.load(from: [item([textProvider("echo hi")])])
        XCTAssertEqual(try result.get(), SharedPayload(text: "echo hi"))
    }

    func testSafariSelectionWithURLAndTitle() async throws {
        let page = URL(string: "https://example.com/how-to")!
        let result = await SharedItemLoader.load(from: [item([urlProvider(page), textProvider("curl -I x")], title: "How to curl")])
        let payload = try result.get()
        XCTAssertEqual(payload.text, "curl -I x")
        XCTAssertEqual(payload.sourceURL, page)
        XCTAssertEqual(payload.pageTitle, "How to curl")
    }

    func testSourceFile() async throws {
        let file = try tempFile("main.swift", contents: Data("print(1)".utf8))
        let payload = try await SharedItemLoader.load(from: [item([urlProvider(file)])]).get()
        XCTAssertEqual(payload.text, "print(1)")
        XCTAssertTrue(payload.fileName?.hasSuffix("main.swift") == true)
    }

    func testURLWithoutTextAsksForSelection() async {
        let result = await SharedItemLoader.load(from: [item([urlProvider(URL(string: "https://example.com")!)])])
        XCTAssertEqual(result, .failure(.noText))
        XCTAssertEqual(ShareProblem.noText.message, "Select the code first, then share.")
    }

    func testHugeFileIsRejected() async throws {
        let file = try tempFile("big.txt", contents: Data(repeating: 65, count: 1_100_000))
        let result = await SharedItemLoader.load(from: [item([urlProvider(file)])])
        XCTAssertEqual(result, .failure(.tooLarge))
    }

    func testNothingShared() async {
        let result = await SharedItemLoader.load(from: [])
        XCTAssertEqual(result, .failure(.noText))
    }
}
