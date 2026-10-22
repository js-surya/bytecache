import ByteCacheCore
import SwiftUI
import UniformTypeIdentifiers

/// One file of a snippet: header with copy button, then the code.
public struct FragmentCard: View {
    let fragment: Fragment
    var snippetTitle = ""
    var onCopy: () -> Void = {}
    @State private var copied = false
    @State private var exporting = false
    @State private var showSource = false
    @State private var sharingImage = false
    #if DEBUG
    /// `-BCShareImage`: open Share as Image once for the first file shown (screenshots).
    @MainActor private static var debugShareImageShown = false
    #endif

    private var isMarkdown: Bool { MarkdownDocument.isMarkdown(language: fragment.language) }

    public init(fragment: Fragment, snippetTitle: String = "", onCopy: @escaping () -> Void = {}) {
        self.fragment = fragment
        self.snippetTitle = snippetTitle
        self.onCopy = onCopy
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pick the first header layout that fits without cutting the file name: one line with a
            // "Copy" label, one line with an icon-only Copy, the Preview/Source switch on its own line,
            // and only then a truncated name.
            ViewThatFits(in: .horizontal) {
                HStack { title.fixedSize(); Spacer(minLength: 8); viewSwitch; imageButton; copyButton(iconOnly: false) }
                HStack { title.fixedSize(); Spacer(minLength: 8); viewSwitch; imageButton; copyButton(iconOnly: true) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { title.fixedSize(); Spacer(minLength: 8); imageButton; copyButton(iconOnly: true) }
                    viewSwitch
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { title; Spacer(minLength: 8); imageButton; copyButton(iconOnly: true) }
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
        .contextMenu {
            Button {
                Pasteboard.copy(fragment.code)
                onCopy()
            } label: { Label("Copy Code", symbol: .copy) }
            Button { sharingImage = true } label: { Label("Share as Image…", symbol: .image) }
            Button { exporting = true } label: { Label("Save File…", symbol: .download) }
        }
        .sheet(isPresented: $sharingImage) {
            NavigationStack { CodeImageSheet(fragment: fragment) }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-BCShareImage"), !Self.debugShareImageShown {
                Self.debugShareImageShown = true
                sharingImage = true
            }
        }
        #endif
        .fileExporter(isPresented: $exporting,
                      document: SnippetFileDocument(wrapper: exportFile.0),
                      contentType: exportFile.1,
                      defaultFilename: exportFile.0.preferredFilename) { _ in }
    }

    private var exportFile: (FileWrapper, UTType) {
        SnippetExport.fileWrapper(for: fragment, snippetTitle: snippetTitle)
    }

    private var title: some View {
        HStack(spacing: 6) {
            Text(fragment.fileName.isEmpty ? "Untitled" : fragment.fileName)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 3) {
                LanguageIconView(fragment.language, size: 12)
                Text(LanguageName.display(fragment.language))
            }
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

    private var imageButton: some View {
        Button { sharingImage = true } label: {
            Label("Share as Image", symbol: .image).labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .help("Share as Image")
        // The icon-only label isn't spoken on its own; give the button its name.
        .accessibilityLabel("Share as Image")
    }

    private func copyButton(iconOnly: Bool) -> some View {
        Button {
            Pasteboard.copy(fragment.code, toast: false)
            onCopy()
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
