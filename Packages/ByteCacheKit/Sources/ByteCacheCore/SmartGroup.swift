import Foundation

/// A saved group that collects snippets by rules. Lives on the device (synced with the settings);
/// ByteStash knows nothing about it.
public struct SmartGroup: Codable, Hashable, Identifiable, Sendable {
    public enum Match: String, Codable, CaseIterable, Sendable {
        case all, any, none

        public var title: String {
            switch self {
            case .all: "All"
            case .any: "Any"
            case .none: "None"
            }
        }
    }

    public var id: UUID
    public var name: String
    public var match: Match
    public var rules: [SmartRule]

    public init(id: UUID = UUID(), name: String, match: Match = .all, rules: [SmartRule] = []) {
        self.id = id
        self.name = name
        self.match = match
        self.rules = rules
    }

    /// With no rules, every snippet matches.
    public func matches(_ snippet: Snippet, now: Date = Date()) -> Bool {
        guard !rules.isEmpty else { return true }
        switch match {
        case .all: return rules.allSatisfy { $0.matches(snippet, now: now) }
        case .any: return rules.contains { $0.matches(snippet, now: now) }
        case .none: return !rules.contains { $0.matches(snippet, now: now) }
        }
    }
}

public struct SmartRule: Codable, Hashable, Identifiable, Sendable {
    public enum Field: String, Codable, CaseIterable, Sendable {
        case title, description, code, language, tag, pinned, favorite, modifiedWithinDays

        public var title: String {
            switch self {
            case .title: "Title"
            case .description: "Description"
            case .code: "Code"
            case .language: "Language"
            case .tag: "Tag"
            case .pinned: "Pinned"
            case .favorite: "Favorite"
            case .modifiedWithinDays: "Modified in the last"
            }
        }

        /// Text fields compare with "contains"; language and tag with "is".
        public var isText: Bool { [.title, .description, .code].contains(self) }
        public var hasValue: Bool { ![.pinned, .favorite].contains(self) }
    }

    public var id: UUID
    public var field: Field
    /// "Doesn't contain" / "is not" / "not pinned".
    public var negated: Bool
    /// Text to look for, a language id, a tag, or a number of days.
    public var value: String

    public init(id: UUID = UUID(), field: Field, negated: Bool = false, value: String = "") {
        self.id = id
        self.field = field
        self.negated = negated
        self.value = value
    }

    public func matches(_ snippet: Snippet, now: Date = Date()) -> Bool {
        let value = value.trimmingCharacters(in: .whitespaces)
        let hit: Bool
        switch field {
        case .title: hit = value.isEmpty || snippet.title.localizedCaseInsensitiveContains(value)
        case .description: hit = value.isEmpty || snippet.description.localizedCaseInsensitiveContains(value)
        case .code: hit = value.isEmpty || snippet.fragments.contains { $0.code.localizedCaseInsensitiveContains(value) }
        case .language: hit = snippet.fragments.contains { $0.language.caseInsensitiveCompare(value) == .orderedSame }
        case .tag: hit = snippet.categories.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
        case .pinned: hit = snippet.isPinned
        case .favorite: hit = snippet.isFavorite
        case .modifiedWithinDays:
            let days = Double(Int(value) ?? 7)
            hit = (snippet.updatedAt ?? .distantPast) >= now.addingTimeInterval(-days * 86_400)
        }
        return negated ? !hit : hit
    }
}
