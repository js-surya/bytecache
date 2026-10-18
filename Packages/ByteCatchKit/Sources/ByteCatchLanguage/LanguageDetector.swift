import Foundation

public struct DetectionResult: Equatable, Sendable {
    /// Best catalog id; `plaintext` when abstaining.
    public var best: String
    /// Up to three quick picks, most likely first.
    public var candidates: [LanguageGuess]
    public var stage: DetectionStage

    public var abstained: Bool { stage == .abstained }
}

/// Hints → shebang → structure → classifier (+ disambiguation) → confidence threshold.
public struct LanguageDetector: Sendable {
    public static let confidenceThreshold = 0.55
    /// Lines of code the classifier sees; keeps huge pastes fast.
    public static let classifierLineLimit = 400

    /// Rules only — used when no trained model is bundled.
    public static let rulesOnly = LanguageDetector(classifier: nil)

    private let classifier: (any LanguageClassifier)?
    private let rules: [(DetectionStage, any RuleStage)] = [
        (.hint, HintStage()), (.shebang, ShebangStage()), (.structural, StructuralStage()),
    ]

    public init(classifier: (any LanguageClassifier)? = CoreMLLanguageClassifier.bundled) {
        self.classifier = classifier
    }

    public func detect(_ input: DetectionInput) -> DetectionResult {
        guard input.text.contains(where: { !$0.isWhitespace }) else {
            return DetectionResult(best: "plaintext", candidates: [], stage: .abstained)
        }
        for (stage, rule) in rules {
            if let id = rule.detect(input) {
                return DetectionResult(best: id, candidates: [LanguageGuess(id: id, confidence: 1)], stage: stage)
            }
        }
        guard let classifier else {
            return DetectionResult(best: "plaintext", candidates: [], stage: .abstained)
        }
        let text = input.text
            .split(separator: "\n", maxSplits: Self.classifierLineLimit, omittingEmptySubsequences: false)
            .prefix(Self.classifierLineLimit)
            .joined(separator: "\n")
        let known = Set(LanguageCatalog.ids)
        let ranked = Disambiguator.refine(text: text, ranked: classifier.rank(text).filter { known.contains($0.id) })
        let candidates = Array(ranked.prefix(3))
        guard let top = candidates.first, top.confidence >= Self.confidenceThreshold else {
            return DetectionResult(best: "plaintext", candidates: candidates, stage: .abstained)
        }
        return DetectionResult(best: top.id, candidates: candidates, stage: .classifier)
    }
}
