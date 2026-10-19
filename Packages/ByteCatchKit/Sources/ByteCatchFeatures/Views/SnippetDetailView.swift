import ByteCatchCore
import SwiftUI

public struct SnippetDetailView: View {
    let snippet: Snippet
    let list: SnippetListModel?
    let onEdit: () -> Void

    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @State private var exporting = false
    @State private var exportFile: ExportFile?
    @State private var exportMessage: String?
    @Environment(\.openWindow) private var openWindow
    let showsOpenInWindow: Bool

    public init(snippet: Snippet, list: SnippetListModel?, showsOpenInWindow: Bool = true, onEdit: @escaping () -> Void) {
        self.snippet = snippet
        self.list = list
        self.showsOpenInWindow = showsOpenInWindow
        self.onEdit = onEdit
    }

    private var wholeSnippet: ExportFile {
        ExportFile(wrapper: SnippetExport.fileWrapper(for: snippet), contentType: SnippetExport.contentType(for: snippet))
    }

    private func save(_ choice: ExportChoice) {
        exportFile = choice.export()
        exporting = true
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
                    if snippet.isPinned || snippet.isFavorite {
                        HStack(spacing: 8) {
                            if snippet.isPinned { StatusChip(title: "Pinned", symbol: .pinFill, color: .orange) }
                            if snippet.isFavorite { StatusChip(title: "Favorite", symbol: .starFill, color: .yellow) }
                        }
                    }
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
                    FragmentCard(fragment: fragment, snippetTitle: snippet.title)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(snippet.title)
        .fileExporter(isPresented: $exporting,
                      document: SnippetFileDocument(wrapper: (exportFile ?? wholeSnippet).wrapper),
                      contentType: (exportFile ?? wholeSnippet).contentType,
                      defaultFilename: (exportFile ?? wholeSnippet).filename) { result in
            if case .failure(let error) = result { exportMessage = error.localizedDescription }
        }
        .alert("Couldn't Save", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                if let list {
                    Button { Task { await list.togglePin(snippet) } } label: {
                        Label(snippet.isPinned ? "Unpin" : "Pin", symbol: snippet.isPinned ? .pinFill : .pin)
                            .foregroundStyle(snippet.isPinned ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                    }
                    Button { Task { await list.toggleFavorite(snippet) } } label: {
                        Label(snippet.isFavorite ? "Unfavorite" : "Favorite", symbol: snippet.isFavorite ? .starFill : .star)
                            .foregroundStyle(snippet.isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tint))
                    }
                }
                ShareLink(item: allCode)
                let choices = SnippetExport.choices(for: snippet)
                if choices.count > 1 {
                    Menu {
                        ForEach(choices) { choice in
                            Button(choice.id == "all" ? "\(choice.title)…" : choice.title) { save(choice) }
                            if choice.id == "all" { Divider() }
                        }
                    } label: {
                        Label("Save", symbol: .download)
                    }
                } else if let only = choices.first {
                    Button { save(only) } label: { Label("Save File…", symbol: .download) }
                }
                if showsOpenInWindow && supportsMultipleWindows {
                    Button { openWindow(value: snippet.id) } label: {
                        Label("Open in New Window", symbol: .newWindow)
                    }
                }
                Button(action: onEdit) { Label("Edit", symbol: .edit) }
            }
        }
    }
}

/// "Pinned" / "Favorite" label under a snippet's title.
struct StatusChip: View {
    let title: String
    let symbol: AppSymbol
    let color: Color

    var body: some View {
        Label { Text(title) } icon: { Icon(symbol, size: 12) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}
