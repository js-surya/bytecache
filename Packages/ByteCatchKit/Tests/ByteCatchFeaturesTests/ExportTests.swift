import XCTest
import ByteCatchCore
import ByteCatchLanguage
import UniformTypeIdentifiers
@testable import ByteCatchFeatures

final class SnippetExportTests: XCTestCase {
    private func fragment(_ name: String, _ code: String = "x", language: String) -> Fragment {
        Fragment(id: nil, fileName: name, code: code, language: language, position: 0)
    }

    private func snippet(_ title: String, _ fragments: [Fragment]) -> Snippet {
        Snippet(id: 1, title: title, description: "", updatedAt: nil, expiryDate: nil, isPublic: false, isPinned: false,
                isFavorite: false, categories: [], fragments: fragments.enumerated().map { i, f in
                    Fragment(id: i, fileName: f.fileName, code: f.code, language: f.language, position: i)
                }, shareCount: 0)
    }

    func testExtensions() {
        XCTAssertEqual(SnippetExport.fileExtension(for: "python"), "py")
        XCTAssertEqual(SnippetExport.fileExtension(for: "javascript"), "js")
        XCTAssertEqual(SnippetExport.fileExtension(for: "typescript"), "ts")
        XCTAssertEqual(SnippetExport.fileExtension(for: "bash"), "sh")
        XCTAssertEqual(SnippetExport.fileExtension(for: "cpp"), "cpp")
        XCTAssertEqual(SnippetExport.fileExtension(for: "csharp"), "cs")
        XCTAssertEqual(SnippetExport.fileExtension(for: "markdown"), "md")
        XCTAssertEqual(SnippetExport.fileExtension(for: "plaintext"), "txt")
        XCTAssertEqual(SnippetExport.fileExtension(for: "something-new"), "txt")
        for id in LanguageCatalog.ids { XCTAssertFalse(SnippetExport.fileExtension(for: id).isEmpty, id) }
    }

    func testSafeNames() {
        XCTAssertEqual(SnippetExport.safeName("Fetch: JSON / API?"), "Fetch- JSON - API-")
        XCTAssertEqual(SnippetExport.safeName("   "), "snippet")
        XCTAssertEqual(SnippetExport.safeName(".hidden"), "hidden")
        XCTAssertEqual(SnippetExport.safeName(String(repeating: "a", count: 300)).count, 100)
    }

    func testSingleFragmentUsesTitleAndLanguageExtension() {
        let s = snippet("Docker cleanup", [fragment("main", language: "bash")])
        XCTAssertEqual(SnippetExport.fileName(for: s), "Docker cleanup.sh")
        XCTAssertEqual(SnippetExport.fileName(for: snippet("run.sh", [fragment("main", language: "bash")])), "run.sh",
                       "no doubled extension")
        XCTAssertEqual(SnippetExport.fileName(for: snippet("Build", [fragment("Dockerfile", language: "dockerfile")])), "Dockerfile")
    }

    func testMultipleFragmentsBecomeAFolderWithUniqueNames() throws {
        let s = snippet("My App", [fragment("app.js", "a", language: "javascript"), fragment("main", "b", language: "css"),
                                   fragment("main", "c", language: "css")])
        let wrapper = SnippetExport.fileWrapper(for: s)
        XCTAssertTrue(wrapper.isDirectory)
        XCTAssertEqual(wrapper.preferredFilename, "My App")
        let names = Set(wrapper.fileWrappers?.keys.map { $0 } ?? [])
        XCTAssertEqual(names, ["app.js", "main.css", "main 2.css"])
        XCTAssertEqual(wrapper.fileWrappers?["app.js"]?.regularFileContents, Data("a".utf8))
    }

    func testSingleFragmentWrapperAndContentType() {
        let s = snippet("Hello", [fragment("main", "print(1)", language: "python")])
        let wrapper = SnippetExport.fileWrapper(for: s)
        XCTAssertFalse(wrapper.isDirectory)
        XCTAssertEqual(wrapper.preferredFilename, "Hello.py")
        XCTAssertEqual(wrapper.regularFileContents, Data("print(1)".utf8))
        XCTAssertTrue(SnippetExport.contentType(for: s).conforms(to: .pythonScript))
        XCTAssertEqual(SnippetExport.contentType(for: snippet("x", [fragment("a", language: "c"), fragment("b", language: "c")])), .folder)
    }
}

final class SnippetExportWriteTests: XCTestCase {
    /// What fileExporter does with the document: write the wrapper to disk.
    func testWrittenFolderContainsEachFile() throws {
        let s = Snippet(id: 1, title: "Web: page", description: "", updatedAt: nil, expiryDate: nil, isPublic: false,
                        isPinned: false, isFavorite: false, categories: [],
                        fragments: [Fragment(id: 1, fileName: "index", code: "<p>", language: "html", position: 0),
                                    Fragment(id: 2, fileName: "style", code: "p{}", language: "css", position: 1)],
                        shareCount: 0)
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let wrapper = SnippetExport.fileWrapper(for: s)
        let target = dir.appending(path: SnippetExport.defaultFilename(for: s))
        try wrapper.write(to: target, options: .atomic, originalContentsURL: nil)
        XCTAssertEqual(target.lastPathComponent, "Web- page")
        XCTAssertEqual(try String(contentsOf: target.appending(path: "index.html"), encoding: .utf8), "<p>")
        XCTAssertEqual(try String(contentsOf: target.appending(path: "style.css"), encoding: .utf8), "p{}")
    }
}

final class SnippetExportChoiceTests: XCTestCase {
    private let snippet = Snippet(
        id: 1, title: "My App", description: "", updatedAt: nil, expiryDate: nil, isPublic: false, isPinned: false,
        isFavorite: false, categories: [],
        fragments: [Fragment(id: 10, fileName: "app.js", code: "a", language: "javascript", position: 0),
                    Fragment(id: 11, fileName: "main", code: "b", language: "css", position: 1)],
        shareCount: 0)

    func testChoicesListAllThenEachFileWithItsSavedName() {
        let choices = SnippetExport.choices(for: snippet)
        XCTAssertEqual(choices.map(\.title), ["All Files (Folder)", "app.js", "My App.css"])
    }

    func testEachChoiceProducesTheRightFile() {
        let choices = SnippetExport.choices(for: snippet)
        let all = choices[0].export()
        XCTAssertTrue(all.wrapper.isDirectory)
        XCTAssertEqual(all.contentType, .folder)
        let css = choices[2].export()
        XCTAssertEqual(css.wrapper.preferredFilename, "My App.css")
        XCTAssertEqual(css.wrapper.regularFileContents, Data("b".utf8))
        XCTAssertTrue(css.contentType.conforms(to: .text))
    }

    func testSingleFileSnippetHasOneChoice() {
        var one = snippet
        one.fragments = [snippet.fragments[0]]
        XCTAssertEqual(SnippetExport.choices(for: one).map(\.title), ["My App.js"])
    }
}
