import XCTest
@testable import ByteCacheFeatures
import ByteCacheCore

/// CP-92: files dropped on the snippet list.
final class DropImportTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "DropImportTests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    func testCodeFileKeepsItsNameAndText() throws {
        let url = try file("retry.py", Data("import time\nprint('hi')\n".utf8))
        XCTAssertEqual(try DropImport.read(url).get(), DroppedFile(name: "retry.py", text: "import time\nprint('hi')\n"))
    }

    func testBinaryFileIsRefused() throws {
        let url = try file("logo.png", Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x00, 0x0D]))
        XCTAssertEqual(DropImport.read(url), .failure(.noText))
    }

    func testEmptyFileIsRefused() throws {
        let url = try file("empty.txt", Data("  \n".utf8))
        XCTAssertEqual(DropImport.read(url), .failure(.noText))
    }

    func testTooLargeFileIsRefused() throws {
        let url = try file("big.txt", Data(repeating: 0x61, count: SharedItemLoader.maxFileBytes + 1))
        XCTAssertEqual(DropImport.read(url), .failure(.tooLarge))
    }

    func testFolderIsRefused() {
        XCTAssertEqual(DropImport.read(folder), .failure(.noText))
    }
}

/// CP-92: a snippet dragged out as code or as its file.
final class SnippetDragItemTests: XCTestCase {
    private func snippet(_ fragments: [(String, String, String)]) -> Snippet {
        Snippet(id: 1, title: "Retry helper", description: "", updatedAt: nil, expiryDate: nil, isPublic: false,
                isPinned: false, isFavorite: false, categories: [],
                fragments: fragments.enumerated().map { i, f in
                    Fragment(id: i + 1, fileName: f.0, code: f.1, language: f.2, position: i)
                }, shareCount: 0)
    }

    func testOneFileIsWrittenUnderItsName() throws {
        let item = SnippetDragItem(snippet([("retry.py", "import time", "python")]))
        XCTAssertEqual(item.code, "import time")
        let url = try item.writeFile()
        XCTAssertEqual(url.lastPathComponent, "Retry helper.py")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "import time")
    }

    func testSeveralFilesBecomeAFolder() throws {
        let item = SnippetDragItem(snippet([("Card.tsx", "a", "tsx"), ("card.css", "b", "css")]))
        XCTAssertEqual(item.code, "a\n\nb")
        let url = try item.writeFile()
        var isFolder: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: url.path)), ["Card.tsx", "card.css"])
    }
}
