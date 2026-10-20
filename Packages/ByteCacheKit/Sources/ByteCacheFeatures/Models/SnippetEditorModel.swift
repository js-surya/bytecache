import ByteCacheCore
import ByteCacheLanguage
import Foundation
import Observation

/// Create or edit a snippet. Saving always sends the full snippet (PUT replaces everything).
@MainActor @Observable
public final class SnippetEditorModel {
    public var draft: SnippetDraft
    /// Detector quick picks per fragment index.
    public private(set) var suggestions: [Int: [LanguageGuess]] = [:]
    public private(set) var isSaving = false
    public private(set) var isSuggesting = false
    public var error: String?

    public let existingID: Int?
    public var isNew: Bool { existingID == nil }
    /// The server the snippet is saved to.
    public var server: ServerURL? { session.client?.server }

    /// Fragment indexes whose language the user chose (or that came from the server); detection leaves them alone.
    @ObservationIgnored private var pinnedLanguages: Set<Int>
    private let session: SessionManager
    private let detector: LanguageDetector
    private let suggester: (any SnippetSuggester)?
    private let knownCategories: [String]

    public init(existing: Snippet?, session: SessionManager, detector: LanguageDetector,
                suggester: (any SnippetSuggester)? = nil, knownCategories: [String] = []) {
        self.session = session
        self.detector = detector
        self.suggester = suggester
        self.knownCategories = knownCategories
        existingID = existing?.id
        if let existing {
            let loaded = SnippetDraft(from: existing)
            draft = loaded
            pinnedLanguages = Set(loaded.fragments.indices)
        } else {
            draft = SnippetDraft(
                title: "", description: "", categories: [],
                fragments: [FragmentDraft(fileName: "", code: "", language: "plaintext")], isPublic: false
            )
            pinnedLanguages = []
        }
    }

    public var canSave: Bool {
        !isSaving && draft.fragments.contains { $0.code.contains { !$0.isWhitespace } }
    }

    // MARK: Fragments

    public func codeChanged(fragment index: Int) {
        guard draft.fragments.indices.contains(index), !pinnedLanguages.contains(index) else { return }
        let fragment = draft.fragments[index]
        let result = detector.detect(DetectionInput(text: fragment.code, fileName: fragment.fileName.isEmpty ? nil : fragment.fileName))
        draft.fragments[index].language = result.best
        suggestions[index] = result.candidates
    }

    public func setLanguage(_ id: String, fragment index: Int) {
        guard draft.fragments.indices.contains(index) else { return }
        draft.fragments[index].language = id
        pinnedLanguages.insert(index)
    }

    public func addFragment() {
        draft.fragments.append(FragmentDraft(fileName: "", code: "", language: "plaintext"))
    }

    public func removeFragment(at offsets: IndexSet) {
        draft.fragments.remove(atOffsets: offsets)
        if draft.fragments.isEmpty { addFragment() }
        // Indexes shifted; re-key per-fragment state conservatively.
        pinnedLanguages = Set(draft.fragments.indices.filter { draft.fragments[$0].language != "plaintext" })
        suggestions = [:]
    }

    public func moveFragment(from source: IndexSet, to destination: Int) {
        draft.fragments.move(fromOffsets: source, toOffset: destination)
        pinnedLanguages = Set(draft.fragments.indices.filter { draft.fragments[$0].language != "plaintext" })
        suggestions = [:]
    }

    // MARK: Suggestions

    public var canSuggest: Bool { suggester != nil }

    /// Fills an empty title, description and categories from the first fragment with code.
    public func suggest() async {
        guard let suggester, !isSuggesting,
              let fragment = draft.fragments.first(where: { $0.code.contains { !$0.isWhitespace } }) else { return }
        isSuggesting = true
        defer { isSuggesting = false }
        guard let suggestion = try? await suggester.suggest(code: fragment.code, language: fragment.language,
                                                            knownCategories: knownCategories) else { return }
        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = suggestion.title }
        if draft.description.trimmingCharacters(in: .whitespaces).isEmpty { draft.description = suggestion.description }
        if draft.categories.isEmpty { draft.categories = suggestion.cleanCategories }
    }

    // MARK: Save

    @discardableResult
    public func save() async throws(APIError) -> Snippet {
        guard let client = session.client else {
            error = ErrorText.message(for: .unauthorized)
            throw .unauthorized
        }
        isSaving = true
        error = nil
        defer { isSaving = false }
        let outgoing = normalized(draft)
        do {
            if let id = existingID {
                return try await client.update(id: id, outgoing)
            } else {
                return try await client.create(outgoing)
            }
        } catch {
            if error == .unauthorized { session.handleUnauthorized() }
            self.error = ErrorText.message(for: error)
            throw error
        }
    }

    private func normalized(_ draft: SnippetDraft) -> SnippetDraft {
        var out = draft
        out.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.title.isEmpty {
            out.title = draft.fragments.map { $0.fileName.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
                ?? "Untitled snippet"
        }
        var seen = Set<String>()
        out.categories = draft.categories
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        out.fragments = draft.fragments.map { fragment in
            var f = fragment
            f.code = fragment.code.replacingOccurrences(of: "\r\n", with: "\n")
            return f
        }
        return out
    }
}
extension SnippetEditorModel: Identifiable {}
