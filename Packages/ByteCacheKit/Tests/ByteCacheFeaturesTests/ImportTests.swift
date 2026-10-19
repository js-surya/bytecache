import XCTest
import ByteCacheCore
import ByteCacheLanguage
import ByteCacheTestSupport
@testable import ByteCacheFeatures

final class GistImportTests: XCTestCase {
    func testGistIDFromLinks() {
        XCTAssertEqual(GistImport.gistID(from: "https://gist.github.com/octocat/aa5a315d61ae9438b18d"), "aa5a315d61ae9438b18d")
        XCTAssertEqual(GistImport.gistID(from: "gist.github.com/aa5a315d61ae9438b18d#file-hello-py"), "aa5a315d61ae9438b18d")
        XCTAssertEqual(GistImport.gistID(from: " aa5a315d61ae9438b18d "), "aa5a315d61ae9438b18d")
        XCTAssertNil(GistImport.gistID(from: "https://github.com/octocat/repo"))
    }

    func testGistBecomesOneCandidateWithAFragmentPerFile() async throws {
        let json = #"{"description":"Hello world tools","files":{"hello.py":{"filename":"hello.py","content":"print('hi')","truncated":false},"run.sh":{"filename":"run.sh","content":"python hello.py","truncated":false}}}"#
        let stub = StubTransport(body: json)
        let candidates = try await GistImport.fetch("https://gist.github.com/u/aa5a315d61ae9438b18d", transport: stub,
                                                    detector: .rulesOnly)
        XCTAssertEqual(stub.last.url?.absoluteString, "https://api.github.com/gists/aa5a315d61ae9438b18d")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].title, "Hello world tools")
        XCTAssertEqual(candidates[0].fragments.map(\.fileName), ["hello.py", "run.sh"])
        XCTAssertEqual(candidates[0].fragments.map(\.language), ["python", "bash"])
    }

    func testGitHubsLanguageIsUsedForGenericFileNames() async throws {
        let json = #"{"description":"tools","files":{"gistfile1.txt":{"filename":"gistfile1.txt","language":"Python","content":"x = 1","truncated":false}}}"#
        let candidates = try await GistImport.fetch("aa5a315d61ae9438b18d", transport: StubTransport(body: json), detector: .rulesOnly)
        XCTAssertEqual(candidates[0].fragments[0].language, "python")
    }

    func testGitHubsGenericTextLabelIsIgnored() async throws {
        let json = #"{"description":"t","files":{"gistfile1.txt":{"filename":"gistfile1.txt","language":"Text","content":"{\"a\": 1}","truncated":false}}}"#
        let candidates = try await GistImport.fetch("aa5a315d61ae9438b18d", transport: StubTransport(body: json), detector: .rulesOnly)
        XCTAssertEqual(candidates[0].fragments[0].language, "json", "detected from the code instead")
    }

    func testMissingGist() async {
        do {
            _ = try await GistImport.fetch("aa5a315d61ae9438b18d", transport: StubTransport(status: 404, body: "{}"), detector: .rulesOnly)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual((error as? ImportError)?.message, "That gist wasn't found. Check the link (secret gists need the full link).")
        }
    }
}

final class VSCodeImportTests: XCTestCase {
    func testParsesEntriesWithCommentsArraysAndScopes() throws {
        let text = """
        {
          // Comment allowed by VS Code
          "Print to console": {
            "scope": "javascript,typescript",
            "prefix": "log",
            "body": ["console.log('$1');", "$2"],
            "description": "Log output to console"
          },
          "Main guard": { "prefix": "main", "body": "if __name__ == '__main__':\\n    main()" },
        }
        """
        let candidates = try VSCodeSnippetImport.parse(Data(text.utf8), fileName: "python.json", detector: .rulesOnly)
        XCTAssertEqual(candidates.map(\.title), ["Print to console", "Main guard"])
        XCTAssertEqual(candidates[0].fragments[0].code, "console.log('$1');\n$2")
        XCTAssertEqual(candidates[0].fragments[0].language, "javascript", "scope wins")
        XCTAssertEqual(candidates[0].description, "Log output to console")
        XCTAssertEqual(candidates[1].fragments[0].language, "python", "file name python.json")
        XCTAssertThrowsError(try VSCodeSnippetImport.parse(Data("not json".utf8), fileName: "x.json", detector: .rulesOnly))
    }
}

final class FileImportTests: XCTestCase {
    func testFolderOfFilesBecomesCandidatesSkippingBinary() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appending(path: "sub"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try Data("SELECT 1;".utf8).write(to: dir.appending(path: "query.sql"))
        try Data("fn main() {}".utf8).write(to: dir.appending(path: "sub/main.rs"))
        try Data([0xFF, 0xD8, 0xFF, 0x00, 0x10]).write(to: dir.appending(path: "photo.jpg"))
        let candidates = FileImport.candidates(from: [dir], detector: .rulesOnly)
        XCTAssertEqual(candidates.map(\.title).sorted(), ["main", "query"])
        XCTAssertEqual(candidates.first { $0.title == "query" }?.fragments.first?.language, "sql")
        XCTAssertEqual(candidates.first { $0.title == "main" }?.fragments.first?.fileName, "main.rs")
    }
}

@MainActor
final class ImportRunTests: XCTestCase {
    func testOnlySelectedCandidatesAreCreated() async throws {
        let (session, transport) = await TestSession.signedIn([.json(TestJSON.snippet(1), status: 201)])
        var a = ImportCandidate(title: "A", fragments: [FragmentDraft(fileName: "a", code: "x", language: "bash")])
        let b = ImportCandidate(title: "B", fragments: [FragmentDraft(fileName: "b", code: "y", language: "bash")])
        a.isSelected = false
        let result = await ImportRunner(session: session).run([a, b])
        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
}
