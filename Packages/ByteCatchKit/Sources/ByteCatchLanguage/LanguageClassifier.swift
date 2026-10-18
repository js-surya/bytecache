import CoreML
import Foundation
import NaturalLanguage

/// Ranks catalog ids for a piece of code, most likely first.
public protocol LanguageClassifier: Sendable {
    func rank(_ text: String) -> [LanguageGuess]
}

/// The bundled Core ML text classifier, fed `CodeTokenizer.features`.
public final class CoreMLLanguageClassifier: LanguageClassifier, @unchecked Sendable {
    /// Nil until a trained model ships in the bundle (Tools/LanguageModelTrainer).
    public static let bundled: CoreMLLanguageClassifier? = {
        guard let model = loadBundledModel() else { return nil }
        return try? CoreMLLanguageClassifier(model: model)
    }()

    private let model: NLModel
    private let lock = NSLock()

    public init(model: MLModel) throws {
        self.model = try NLModel(mlModel: model)
    }

    public func rank(_ text: String) -> [LanguageGuess] {
        let hypotheses = lock.withLock {
            model.predictedLabelHypotheses(for: CodeTokenizer.features(text), maximumCount: Disambiguator.rankingWindow)
        }
        return hypotheses
            .map { LanguageGuess(id: $0.key, confidence: $0.value) }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Xcode compiles the model to `.mlmodelc`; plain SwiftPM may ship the source `.mlmodel`.
    private static func loadBundledModel() -> MLModel? {
        if let compiled = Bundle.module.url(forResource: "ByteCatchLanguage", withExtension: "mlmodelc") {
            return try? MLModel(contentsOf: compiled)
        }
        guard let source = Bundle.module.url(forResource: "ByteCatchLanguage", withExtension: "mlmodel"),
              let compiled = try? MLModel.compileModel(at: source) else { return nil }
        return try? MLModel(contentsOf: compiled)
    }
}
