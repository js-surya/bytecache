import XCTest
@testable import ByteCacheLanguage

/// Acceptance bar from the design spec, measured on held-out chunks of the training sources
/// (files never seen in training). Uses the bundled model plus all rule stages.
final class LanguageEvalTests: XCTestCase {
    struct Chunk: Decodable { let id: String; let band: String; let lines: Int; let text: String }

    private static let chunks: [Chunk] = {
        guard let url = Bundle.module.url(forResource: "heldout", withExtension: "jsonl", subdirectory: "Fixtures"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(Chunk.self, from: Data($0.utf8)) }
    }()

    private func detector() throws -> LanguageDetector {
        guard let classifier = CoreMLLanguageClassifier.bundled else { throw XCTSkip("No trained model bundled") }
        return LanguageDetector(classifier: classifier)
    }

    func testFiveTo200LinesAccuracy() throws {
        let detector = try detector()
        let chunks = Self.chunks.filter { $0.band != "short" }
        XCTAssertGreaterThan(chunks.count, 500)
        var top1 = 0, top3 = 0
        for chunk in chunks {
            let result = detector.detect(DetectionInput(text: chunk.text))
            if result.best == chunk.id { top1 += 1 }
            if result.best == chunk.id || result.candidates.contains(where: { $0.id == chunk.id }) { top3 += 1 }
        }
        let a1 = Double(top1) / Double(chunks.count), a3 = Double(top3) / Double(chunks.count)
        print(String(format: "5–200 lines: top-1 %.3f, top-3 %.3f (n=%d)", a1, a3, chunks.count))
        XCTAssertGreaterThanOrEqual(a1, 0.92)
        XCTAssertGreaterThanOrEqual(a3, 0.98)
    }

    /// Short chunks count as correct when right, or when the detector abstains with the right
    /// language among its three quick picks (the user taps it).
    func testShortSnippetAccuracy() throws {
        let detector = try detector()
        let chunks = Self.chunks.filter { $0.band == "short" }
        XCTAssertGreaterThan(chunks.count, 500)
        let correct = chunks.filter { chunk in
            let result = detector.detect(DetectionInput(text: chunk.text))
            return result.best == chunk.id || (result.abstained && result.candidates.contains { $0.id == chunk.id })
        }.count
        let accuracy = Double(correct) / Double(chunks.count)
        print(String(format: "1–4 lines: %.3f (n=%d)", accuracy, chunks.count))
        XCTAssertGreaterThanOrEqual(accuracy, 0.85)
    }

    func testDetectionSpeedFor200Lines() throws {
        let detector = try detector()
        let code = Self.chunks.first { $0.lines >= 150 }?.text ?? String(repeating: "let x = foo(1)\n", count: 200)
        _ = detector.detect(DetectionInput(text: code)) // warm up
        let runs = 20
        let start = Date()
        for _ in 0..<runs { _ = detector.detect(DetectionInput(text: code)) }
        let average = Date().timeIntervalSince(start) / Double(runs)
        print(String(format: "200-line detection: %.1f ms", average * 1000))
        XCTAssertLessThan(average, 0.030)
    }

    func testModelIsAtMostFiveMegabytes() throws {
        // The source model in the package (SwiftPM may ship it compiled as a folder).
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/ByteCacheLanguage/Resources/ByteCacheLanguage.mlmodel")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? .max
        XCTAssertLessThanOrEqual(size, 5_000_000)
    }
}

/// Hand-picked real-world snippets, including look-alike pairs. File name prefix = expected id.
final class RegressionTests: XCTestCase {
    func testEveryFixtureDetectsItsLanguage() throws {
        guard let classifier = CoreMLLanguageClassifier.bundled else { throw XCTSkip("No trained model bundled") }
        let detector = LanguageDetector(classifier: classifier)
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "regression", withExtension: nil, subdirectory: "Fixtures"))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
        XCTAssertGreaterThanOrEqual(files.count, 55)
        var failures: [String] = []
        for file in files {
            let expected = String(file.lastPathComponent.split(separator: "__")[0])
            let result = detector.detect(DetectionInput(text: try String(contentsOf: file, encoding: .utf8)))
            if result.best != expected {
                failures.append("\(file.lastPathComponent): got \(result.best) \(result.candidates.map { "\($0.id) \(String(format: "%.2f", $0.confidence))" })")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\n" + failures.sorted().joined(separator: "\n"))
    }
}
