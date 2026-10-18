import ByteCatchCore
import SwiftUI

public struct SnippetRow: View {
    let snippet: Snippet

    public init(snippet: Snippet) {
        self.snippet = snippet
    }

    private var firstFragment: Fragment? {
        snippet.fragments.min { $0.position < $1.position }
    }

    private var preview: String {
        firstFragment?.code.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if snippet.isPinned { Image(systemName: "pin.fill").foregroundStyle(.orange).imageScale(.small) }
                if snippet.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow).imageScale(.small) }
                Text(snippet.title.isEmpty ? "Untitled snippet" : snippet.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            if !preview.isEmpty {
                Text(preview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if let language = firstFragment?.language {
                    Text(LanguageName.display(language))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
                if snippet.fragments.count > 1 {
                    Text("\(snippet.fragments.count) files").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(snippet.categories.prefix(3), id: \.self) { category in
                    Text("#\(category)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let date = snippet.updatedAt {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
