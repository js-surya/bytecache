import ByteCatchCore
import SwiftUI

public struct SnippetDetailView: View {
    let snippet: Snippet
    let list: SnippetListModel?
    let onEdit: () -> Void

    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow
    let showsOpenInWindow: Bool

    public init(snippet: Snippet, list: SnippetListModel?, showsOpenInWindow: Bool = true, onEdit: @escaping () -> Void) {
        self.snippet = snippet
        self.list = list
        self.showsOpenInWindow = showsOpenInWindow
        self.onEdit = onEdit
    }

    private var fragments: [Fragment] { snippet.fragments.sorted { $0.position < $1.position } }
    private var allCode: String { fragments.map(\.code).joined(separator: "\n\n") }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snippet.title.isEmpty ? "Untitled snippet" : snippet.title)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    if !snippet.description.isEmpty {
                        Text(snippet.description).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if !snippet.categories.isEmpty {
                        HStack {
                            ForEach(snippet.categories, id: \.self) { category in
                                Text("#\(category)")
                                    .font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.tint.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
                ForEach(fragments) { fragment in
                    FragmentCard(fragment: fragment)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(snippet.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                if let list {
                    Button { Task { await list.togglePin(snippet) } } label: {
                        Label(snippet.isPinned ? "Unpin" : "Pin", systemImage: snippet.isPinned ? "pin.fill" : "pin")
                    }
                    Button { Task { await list.toggleFavorite(snippet) } } label: {
                        Label(snippet.isFavorite ? "Unfavorite" : "Favorite", systemImage: snippet.isFavorite ? "star.fill" : "star")
                    }
                }
                ShareLink(item: allCode)
                if showsOpenInWindow && supportsMultipleWindows {
                    Button { openWindow(value: snippet.id) } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                }
                Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}
