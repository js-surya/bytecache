import XCTest
@testable import ByteCatchFeatures

struct StubExplainer: SnippetExplainer {
    var result: Result<String, Error>
    func explain(code: String, language: String, title: String) async throws -> String { try result.get() }
}

@MainActor
final class ExplainModelTests: XCTestCase {
    func testExplanationShownAfterLoading() async {
        let model = ExplainModel(explainer: StubExplainer(result: .success("Deletes **unused** Docker data.")))
        XCTAssertEqual(model.state, .idle)
        await model.explain(code: "docker system prune -af", language: "bash", title: "Cleanup")
        XCTAssertEqual(model.state, .done("Deletes **unused** Docker data."))
    }

    func testFailureShowsFriendlyMessage() async {
        struct Boom: Error {}
        let model = ExplainModel(explainer: StubExplainer(result: .failure(Boom())))
        await model.explain(code: "x", language: "bash", title: "t")
        XCTAssertEqual(model.state, .failed("Apple Intelligence couldn't explain this snippet right now. Try again in a moment."))
    }

    func testVeryLongCodeIsTrimmedForTheModel() {
        let long = String(repeating: "a", count: 20_000)
        XCTAssertEqual(ExplainModel.prepared(long).count, ExplainModel.maxCharacters)
    }
}
