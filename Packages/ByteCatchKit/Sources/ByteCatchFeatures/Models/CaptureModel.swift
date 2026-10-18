import ByteCatchCore
import ByteCatchLanguage
import Foundation
import Observation

/// Quick save of one piece of code: share extensions, clipboard catch, drag and drop, App Intents.
@MainActor @Observable
public final class CaptureModel {
    public static let signInMessage = "Open ByteCatch and sign in, then try again."

    public var text: String
    public var title: String
    public private(set) var language = "plaintext"
    public private(set) var candidates: [LanguageGuess] = []
    public var categories: [String] = []
    public private(set) var isSaving = false
    public var error: String?

    public let fileName: String?
    public let sourceURL: URL?
    public var signedOut: Bool { client == nil }

    public var canSave: Bool {
        !signedOut && !isSaving && text.contains { !$0.isWhitespace }
    }

    @ObservationIgnored private var languagePicked = false
    private let client: APIClient?
    private let detector: LanguageDetector
    private let onUnauthorized: () -> Void

    public init(
        text: String, fileName: String? = nil, sourceURL: URL? = nil, pageTitle: String? = nil,
        client: APIClient?, detector: LanguageDetector, onUnauthorized: @escaping () -> Void = {}
    ) {
        self.text = text
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.client = client
        self.detector = detector
        self.onUnauthorized = onUnauthorized
        title = Self.defaultTitle(text: text, fileName: fileName, pageTitle: pageTitle)
        detect()
    }

    public func textChanged() {
        if !languagePicked { detect() }
    }

    public func pickLanguage(_ id: String) {
        language = id
        languagePicked = true
    }

    @discardableResult
    public func save() async throws(APIError) -> Snippet {
        guard let client else {
            error = Self.signInMessage
            throw .unauthorized
        }
        isSaving = true
        error = nil
        defer { isSaving = false }
        var seen = Set<String>()
        let draft = SnippetDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.defaultTitle(text: text, fileName: fileName, pageTitle: nil) : title,
            description: sourceURL.map { "Saved from \($0.absoluteString)" } ?? "",
            categories: categories.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty && seen.insert($0).inserted },
            fragments: [FragmentDraft(
                fileName: fileName ?? "snippet",
                code: text.replacingOccurrences(of: "\r\n", with: "\n"),
                language: language
            )],
            isPublic: false
        )
        do {
            return try await client.create(draft)
        } catch {
            if error == .unauthorized {
                onUnauthorized()
                self.error = Self.signInMessage
            } else {
                self.error = ErrorText.message(for: error)
            }
            throw error
        }
    }

    private func detect() {
        let result = detector.detect(DetectionInput(text: text, fileName: fileName, sourceURL: sourceURL))
        language = result.best
        candidates = result.candidates
    }

    static func defaultTitle(text: String, fileName: String?, pageTitle: String?) -> String {
        if let pageTitle = pageTitle?.trimmingCharacters(in: .whitespaces), !pageTitle.isEmpty { return pageTitle }
        if let fileName, !fileName.isEmpty { return fileName }
        let firstLine = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return String(firstLine.prefix(60))
    }
}

extension CaptureModel: Identifiable {}
