import ByteCacheCore
import SwiftUI

public struct SnippetRow: View {
    let snippet: Snippet
    var showOwner = false
    /// The current search, highlighted in the title, description and code preview.
    var search = ""
    /// Whether the search looks inside code, so the preview can show the matching line.
    var searchCode = false

    public init(snippet: Snippet, showOwner: Bool = false, search: String = "", searchCode: Bool = false) {
        self.snippet = snippet
        self.showOwner = showOwner
        self.search = search
        self.searchCode = searchCode
    }

    private var firstFragment: Fragment? {
        snippet.fragments.min { $0.position < $1.position }
    }

    private var preview: String {
        if searchCode {
            for fragment in snippet.fragments.sorted(by: { $0.position < $1.position }) {
                if let line = SearchHighlight.matchingLine(in: fragment.code, query: search) { return line }
            }
        }
        return firstFragment?.code.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    /// Shown only while it holds a match, since rows don't show descriptions otherwise.
    private var matchingDescription: String? {
        SearchHighlight.matchingLine(in: snippet.description, query: search)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = SearchHighlight.mark(text, query: search)
        for run in result.runs where run.inlinePresentationIntent == .stronglyEmphasized {
            result[run.range].swiftUI.backgroundColor = .yellow.opacity(0.35)
        }
        return result
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    public var body: some View {
        // At accessibility sizes the details stack instead of squeezing into one line.
        let details = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 6))
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if snippet.isPinned { Icon(.pinFill, size: 13).foregroundStyle(.orange).imageScale(.small) }
                if snippet.isFavorite { Icon(.starFill, size: 13).foregroundStyle(.yellow).imageScale(.small) }
                if snippet.isPublic && !showOwner { Icon(.globe, size: 13).foregroundStyle(.blue).imageScale(.small) }
                Text(highlighted(snippet.title.isEmpty ? "Untitled snippet" : snippet.title))
                    .font(.headline)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            if let matchingDescription {
                Text(highlighted(matchingDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !preview.isEmpty {
                Text(highlighted(preview))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            details {
                if let language = firstFragment?.language {
                    HStack(spacing: 3) {
                        LanguageIconView(language, size: 11)
                        Text(LanguageName.display(language))
                    }
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
                if snippet.fragments.count > 1 {
                    Text("\(snippet.fragments.count) files").font(.caption2).foregroundStyle(.secondary)
                }
                if showOwner, let owner = snippet.username {
                    Text("by \(owner)").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(snippet.categories.prefix(3), id: \.self) { category in
                    Text("#\(category)").font(.caption2).foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let date = snippet.updatedAt {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(status)
    }

    /// The pin, star and globe markers, which are icons only.
    private var status: String {
        var parts: [String] = []
        if snippet.isPinned { parts.append("Pinned") }
        if snippet.isFavorite { parts.append("Favorite") }
        if snippet.isPublic && !showOwner { parts.append("Public") }
        return parts.joined(separator: ", ")
    }
}
