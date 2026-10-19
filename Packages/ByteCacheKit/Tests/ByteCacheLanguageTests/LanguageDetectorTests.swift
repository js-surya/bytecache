import XCTest
@testable import ByteCacheLanguage

/// Returns a fixed ranking and records what it was asked.
final class StubClassifier: LanguageClassifier, @unchecked Sendable {
    let ranking: [LanguageGuess]
    private(set) var received: [String] = []
    init(_ ranking: [LanguageGuess]) { self.ranking = ranking }
    func rank(_ text: String) -> [LanguageGuess] {
        received.append(text)
        return ranking
    }
}

final class LanguageDetectorTests: XCTestCase {
    private let swiftFirst = [LanguageGuess(id: "swift", confidence: 0.9), LanguageGuess(id: "kotlin", confidence: 0.05),
                              LanguageGuess(id: "scala", confidence: 0.03), LanguageGuess(id: "go", confidence: 0.02)]

    func testHintBeatsClassifier() {
        let classifier = StubClassifier(swiftFirst)
        let result = LanguageDetector(classifier: classifier).detect(DetectionInput(text: "x = 1", fileName: "a.py"))
        XCTAssertEqual(result.best, "python")
        XCTAssertEqual(result.stage, .hint)
        XCTAssertEqual(result.candidates.first?.id, "python")
    }

    func testRulesRunInOrder() {
        let detector = LanguageDetector(classifier: StubClassifier(swiftFirst))
        XCTAssertEqual(detector.detect(DetectionInput(text: "#!/bin/bash\necho hi")).stage, .shebang)
        XCTAssertEqual(detector.detect(DetectionInput(text: #"{"a": 1}"#)).stage, .structural)
    }

    func testConfidentClassifierWinsWithTopThreeCandidates() {
        let result = LanguageDetector(classifier: StubClassifier(swiftFirst)).detect(DetectionInput(text: "let x = 1"))
        XCTAssertEqual(result.best, "swift")
        XCTAssertEqual(result.stage, .classifier)
        XCTAssertEqual(result.candidates.map(\.id), ["swift", "kotlin", "scala"])
        XCTAssertFalse(result.abstained)
    }

    func testLowConfidenceAbstainsToPlaintextButKeepsCandidates() {
        let unsure = [LanguageGuess(id: "c", confidence: 0.40), LanguageGuess(id: "cpp", confidence: 0.35),
                      LanguageGuess(id: "java", confidence: 0.1)]
        let result = LanguageDetector(classifier: StubClassifier(unsure)).detect(DetectionInput(text: "int x;"))
        XCTAssertEqual(result.best, "plaintext")
        XCTAssertTrue(result.abstained)
        XCTAssertEqual(result.candidates.map(\.id), ["c", "cpp", "java"])
    }

    func testEmptyTextAbstainsWithoutCandidates() {
        let classifier = StubClassifier(swiftFirst)
        let result = LanguageDetector(classifier: classifier).detect(DetectionInput(text: "  \n\t "))
        XCTAssertEqual(result.best, "plaintext")
        XCTAssertTrue(result.abstained)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(classifier.received.isEmpty)
    }

    func testHugeInputOnlySendsFirst400LinesToClassifier() {
        let classifier = StubClassifier(swiftFirst)
        let code = (1...5_000).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        _ = LanguageDetector(classifier: classifier).detect(DetectionInput(text: code))
        XCTAssertEqual(classifier.received.first?.split(separator: "\n").count, 400)
    }

    func testClassifierIdsOutsideCatalogAreDropped() {
        let odd = [LanguageGuess(id: "brainfuck", confidence: 0.8), LanguageGuess(id: "ruby", confidence: 0.15)]
        let result = LanguageDetector(classifier: StubClassifier(odd)).detect(DetectionInput(text: "puts 1"))
        XCTAssertEqual(result.candidates.map(\.id), ["ruby"])
    }

    func testRulesOnlyDetectorAbstainsOnPlainCode() {
        let result = LanguageDetector.rulesOnly.detect(DetectionInput(text: "let x = 1"))
        XCTAssertEqual(result.best, "plaintext")
        XCTAssertTrue(result.abstained)
    }

    func testStructuralAnswerStillOffersClassifierQuickPicks() {
        let result = LanguageDetector(classifier: StubClassifier(swiftFirst)).detect(DetectionInput(text: #"{"a": 1}"#))
        XCTAssertEqual(result.best, "json")
        XCTAssertEqual(result.candidates.map(\.id), ["json", "swift", "kotlin"])
    }
}
