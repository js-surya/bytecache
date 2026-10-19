import ByteCatchCore
import SwiftUI

/// One file of a snippet: header with copy button, then the code.
public struct FragmentCard: View {
    let fragment: Fragment
    @State private var copied = false
    @State private var showSource = false

    private var isMarkdown: Bool { MarkdownDocument.isMarkdown(language: fragment.language) }

    public init(fragment: Fragment) {
        self.fragment = fragment
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(fragment.fileName.isEmpty ? "Untitled" : fragment.fileName)
                    .font(.subheadline.weight(.semibold))
                Text(LanguageName.display(fragment.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isMarkdown {
                    Picker("View", selection: $showSource) {
                        Text("Preview").tag(false)
                        Text("Source").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                }
                Button {
                    Pasteboard.copy(fragment.code)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", symbol: copied ? .check : .copy)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            Divider()
            if isMarkdown && !showSource {
                MarkdownView(fragment.code)
            } else {
                CodeView(code: fragment.code, language: fragment.language)
            }
        }
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .draggable(fragment.code)
    }
}
