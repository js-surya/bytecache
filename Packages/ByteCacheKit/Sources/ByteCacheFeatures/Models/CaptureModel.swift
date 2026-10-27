import ByteCacheCore
import ByteCacheLanguage
import Foundation
import Observation

/// Quick save of one piece of code: share extensions, clipboard catch, drag and drop, App Intents.
@MainActor @Observable
public final class CaptureModel {
    public static let signInMessage = "Open ByteCache and sign in, then try again."

    public var text: String
    public var title: String
    public private(set) var language = "plaintext"
    public private(set) var candidates: [LanguageGuess] = []
    public var categories: [String] = []
    /// Filled by suggestions; saved before the "Saved from" line.
    public var snippetDescription = ""
    public private(set) var isSaving = false
    public private(set) var isSuggesting = false
    public var error: String?
    /// The last save failed offline and went to the pending queue instead.
    public private(set) var didQueue = false

    public let fileName: String?
    /// The code was read from a picture (Scan): the review screen reminds to check brackets (CP-84).
    public var readFromImage = false
    public let sourceURL: URL?
    public var signedOut: Bool { client == nil }

    public var canSave: Bool {
        !signedOut && !isSaving && text.contains { !$0.isWhitespace }
    }

    @ObservationIgnored private var languagePicked = false
    @ObservationIgnored private let defaultTitle: String
    private let client: APIClient?
    private let detector: LanguageDetector
    private let suggester: (any SnippetSuggester)?
    private let knownCategories: [String]
    private let queue: PendingSaveQueue?
    private let onUnauthorized: () -> Void

    public init(
        text: String, fileName: String? = nil, sourceURL: URL? = nil, pageTitle: String? = nil,
        client: APIClient?, detector: LanguageDetector, suggester: (any SnippetSuggester)? = nil,
        knownCategories: [String] = [], queue: PendingSaveQueue? = nil,
        onUnauthorized: @escaping () -> Void = {}
    ) {
        self.text = text
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.client = client
        self.detector = detector
        self.suggester = suggester
        self.knownCategories = knownCategories
        self.queue = queue
        self.onUnauthorized = onUnauthorized
        let initialTitle = Self.defaultTitle(text: text, fileName: fileName, pageTitle: pageTitle)
        title = initialTitle
        defaultTitle = initialTitle
        detect()
    }

    public func textChanged() {
        if !languagePicked { detect() }
    }

    public func pickLanguage(_ id: String) {
        language = id
        languagePicked = true
    }

    public var canSuggest: Bool { suggester != nil }
    /// Suggest as soon as the sheet opens: only on device, never sending code without a tap.
    public var suggestsOnOpen: Bool { suggester?.runsOnDevice ?? false }

    /// Fills the title (if still the default), description and categories (if empty).
    public func suggest() async {
        guard let suggester, !isSuggesting, text.contains(where: { !$0.isWhitespace }) else { return }
        isSuggesting = true
        defer { isSuggesting = false }
        guard let suggestion = try? await suggester.suggest(code: text, language: language, knownCategories: knownCategories)
        else { return }
        let suggestedTitle = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !suggestedTitle.isEmpty, title.trimmingCharacters(in: .whitespaces).isEmpty || title == defaultTitle {
            title = suggestedTitle
        }
        if snippetDescription.isEmpty { snippetDescription = suggestion.description.trimmingCharacters(in: .whitespacesAndNewlines) }
        if categories.isEmpty { categories = suggestion.cleanCategories }
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
            description: [snippetDescription, sourceURL.map { "Saved from \($0.absoluteString)" } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: "\n\n"),
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
            let saved = try await client.create(draft)
            AppLog.shared.record("capture", "saved: \(FragmentDraft.logSummary(draft.fragments))")
            return saved
        } catch {
            AppLog.shared.record("capture", "save failed: \(error.logName)")
            if error == .offline, let queue, (try? queue.enqueue(draft, server: client.server)) != nil {
                didQueue = true
                self.error = nil
                AppLog.shared.record("capture", "offline; saved on the device to upload later")
            } else if error == .unauthorized {
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
