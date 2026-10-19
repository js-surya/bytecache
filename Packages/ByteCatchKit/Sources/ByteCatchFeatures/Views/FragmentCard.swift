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
            // Pick the first header layout that fits: one line with a "Copy" label, one line with an
            // icon-only Copy, or the Preview/Source switch on its own line.
            ViewThatFits(in: .horizontal) {
                HStack { title; Spacer(minLength: 8); viewSwitch; copyButton(iconOnly: false) }
                HStack { title; Spacer(minLength: 8); viewSwitch; copyButton(iconOnly: true) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { title; Spacer(minLength: 8); copyButton(iconOnly: true) }
                    viewSwitch
                }
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

    private var title: some View {
        HStack(spacing: 6) {
            Text(fragment.fileName.isEmpty ? "Untitled" : fragment.fileName)
                .font(.subheadline.weight(.semibold))
            Text(LanguageName.display(fragment.language))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var viewSwitch: some View {
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
    }

    private func copyButton(iconOnly: Bool) -> some View {
        Button {
            Pasteboard.copy(fragment.code)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy", symbol: copied ? .check : .copy)
                .labelStyle(iconOnly ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(copied ? "Copied" : "Copy code")
    }
}

/// Lets one call site switch label styles.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(S.makeBody(style)(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
