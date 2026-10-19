import XCTest
@testable import ByteCacheLanguage

final class DisambiguatorTests: XCTestCase {
    private func ranked(_ ids: String...) -> [LanguageGuess] {
        ids.enumerated().map { LanguageGuess(id: $1, confidence: [0.5, 0.3, 0.1, 0.06, 0.04][$0]) }
    }

    private func top(_ text: String, _ candidates: [LanguageGuess]) -> String? {
        Disambiguator.refine(text: text, ranked: candidates).first?.id
    }

    func testCppSignalsBeatC() {
        XCTAssertEqual(top("#include <vector>\nstd::vector<int> v;", ranked("c", "cpp")), "cpp")
        XCTAssertEqual(top("class Foo {\npublic:\n  int x;\n};", ranked("c", "cpp")), "cpp")
        XCTAssertEqual(top("template <typename T> T max(T a, T b);", ranked("c", "cpp")), "cpp")
    }

    func testPlainCStaysC() {
        XCTAssertEqual(top("#include <stdio.h>\nint main(void) { printf(\"hi\"); }", ranked("cpp", "c")), "c")
    }

    func testTypeScriptSignals() {
        XCTAssertEqual(top("const n: number = 1;", ranked("javascript", "typescript")), "typescript")
        XCTAssertEqual(top("interface User {\n  name: string\n}", ranked("javascript", "typescript")), "typescript")
        XCTAssertEqual(top("const x = [1, 2] as const;", ranked("javascript", "typescript")), "typescript")
        XCTAssertEqual(top("const add = (a, b) => a + b;", ranked("javascript", "typescript")), "javascript")
    }

    func testKotlinSwiftScala() {
        XCTAssertEqual(top("fun main() {\n  val x = y ?: 0\n}", ranked("swift", "kotlin", "scala")), "kotlin")
        XCTAssertEqual(top("guard let x = y else { return }", ranked("kotlin", "swift")), "swift")
        XCTAssertEqual(top("func greet() -> String { \"hi\" }", ranked("kotlin", "swift")), "swift")
        XCTAssertEqual(top("case class Point(x: Int)\nobject Main { def run() = 1 }", ranked("kotlin", "scala")), "scala")
    }

    func testPowerShellSignals() {
        XCTAssertEqual(top("Get-ChildItem | Where-Object { $_.Length -gt 1kb }", ranked("bash", "powershell")), "powershell")
        XCTAssertEqual(top("if [ -f x ]; then echo hi; fi", ranked("powershell", "bash")), "bash")
    }

    func testNeverInventsLanguagesOutsideCandidates() {
        XCTAssertEqual(top("std::vector<int> v;", ranked("java", "csharp")), "java")
    }

    func testKeepsAllCandidates() {
        let input = ranked("c", "cpp", "java")
        let output = Disambiguator.refine(text: "std::string s;", ranked: input)
        XCTAssertEqual(Set(output.map(\.id)), Set(input.map(\.id)))
        XCTAssertGreaterThanOrEqual(output[0].confidence, LanguageDetector.confidenceThreshold)
    }

    func testRuleOnlyLanguagesAreStructural() {
        let stage = StructuralStage()
        XCTAssertEqual(stage.detect(DetectionInput(text: "@echo off\nset X=1\necho %X%")), "batch")
        XCTAssertEqual(stage.detect(DetectionInput(text: "REM build\ncall build.cmd %~dp0")), "batch")
        XCTAssertEqual(stage.detect(DetectionInput(text: "db.users.find({ age: { $gt: 30 } })")), "mongodb")
        XCTAssertEqual(stage.detect(DetectionInput(text: "MATCH (p:Person)-[:KNOWS]->(f)\nRETURN p.name, f.name")), "cypher")
        XCTAssertNil(stage.detect(DetectionInput(text: "const db = connect();\ndb.close();")))
    }

    func testConfirmingSignalsLiftUnsureTopChoice() {
        let unsure = [LanguageGuess(id: "bash", confidence: 0.47), LanguageGuess(id: "css", confidence: 0.17)]
        let out = Disambiguator.refine(text: "sudo apt update && sudo apt install -y git", ranked: unsure)
        XCTAssertEqual(out.first?.id, "bash")
        XCTAssertGreaterThanOrEqual(out.first!.confidence, LanguageDetector.confidenceThreshold)
    }

    func testJavaSignals() {
        XCTAssertEqual(top("System.out.println(x);", ranked("apex", "java")), "java")
        XCTAssertEqual(top("import java.util.List;", ranked("kotlin", "java")), "java")
    }

    func testPythonSignals() {
        XCTAssertEqual(top("squares = [x for x in range(10)]", ranked("julia", "python")), "python")
        XCTAssertEqual(top("from os import path", ranked("julia", "python")), "python")
        XCTAssertEqual(top("@external\ndef __init__():\n    self.owner = msg.sender", ranked("vyper", "python")), "vyper",
                       "Vyper decorators keep Vyper")
    }

    func testGraphQLOperationsAreStructural() {
        let stage = StructuralStage()
        XCTAssertEqual(stage.detect(DetectionInput(text: "query GetUser($id: ID!) {\n  user(id: $id) { name }\n}")), "graphql")
        XCTAssertEqual(stage.detect(DetectionInput(text: "mutation {\n  addStar(input: {}) { clientMutationId }\n}")), "graphql")
        XCTAssertEqual(stage.detect(DetectionInput(text: "fragment F on User {\n  name\n}")), "graphql")
        XCTAssertNil(stage.detect(DetectionInput(text: "query = db.query(sql)")))
    }

    func testVimScriptAndPowerShellVersusYAML() {
        let unsureVim = [LanguageGuess(id: "vimscript", confidence: 0.54), LanguageGuess(id: "markdown", confidence: 0.35)]
        let vim = Disambiguator.refine(text: "set number\nnnoremap <leader>w :w<CR>", ranked: unsureVim)
        XCTAssertGreaterThanOrEqual(vim[0].confidence, LanguageDetector.confidenceThreshold)
        XCTAssertEqual(top("Get-ChildItem | Where-Object { $_.Length -gt 0 }", ranked("yaml", "powershell")), "powershell")
        XCTAssertEqual(top("squares = [x for x in range(10)]", ranked("matlab", "elm", "julia", "python")), "python")
    }

    func testStrongSignalReachesDeeperIntoTheRanking() {
        let ids = ["matlab", "elm", "julia", "groovy", "cpp", "ruby", "r", "python"]
        let deep = ids.enumerated().map { LanguageGuess(id: $1, confidence: 0.6 / Double($0 + 1)) }
        XCTAssertEqual(Disambiguator.refine(text: "for x in range(3): pass", ranked: deep).first?.id, "python")
    }
}
