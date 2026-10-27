import ByteCacheCore
import SwiftUI

/// Compact save form shared by the share extensions, clipboard catch and drag and drop.
public struct CaptureSheet: View {
    @Bindable var model: CaptureModel
    let knownCategories: [String]
    let onDone: (Snippet?) -> Void
    let onQueued: () -> Void
    let emptyHint: String
    let inlineButtons: Bool

    /// `onQueued` runs when the save went to the offline queue instead of the server. `inlineButtons`
    /// puts Cancel and Save under the form, for places without a toolbar (the menu bar window).
    public init(model: CaptureModel, knownCategories: [String] = [],
                emptyHint: String = "Select the code first, then share.", inlineButtons: Bool = false,
                onQueued: @escaping () -> Void = {}, onDone: @escaping (Snippet?) -> Void) {
        self.model = model
        self.knownCategories = knownCategories
        self.emptyHint = emptyHint
        self.inlineButtons = inlineButtons
        self.onQueued = onQueued
        self.onDone = onDone
    }

    public var body: some View {
        Form {
            if model.signedOut {
                Section {
                    Label(CaptureModel.signInMessage, symbol: .signedOut)
                    Button { Pasteboard.copy(model.text) } label: { Label("Copy Code", symbol: .copy) }
                }
            }
            if !SecretScanner.scan(model.text).isEmpty {
                Section { SecretWarning(text: $model.text) }
            }
            Section("Code") {
                CodeEditorView(text: $model.text, language: model.language)
                    .frame(minHeight: 140, idealHeight: 220, maxHeight: 260)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                    .onChange(of: model.text) { model.textChanged() }
                if !model.text.contains(where: { !$0.isWhitespace }) {
                    Text(emptyHint).font(.footnote).foregroundStyle(.secondary)
                } else if model.readFromImage {
                    // Where it matters: next to the text that was read (CP-84).
                    Label("Read from a picture: check brackets and indentation before saving.", symbol: .warning)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                TextField("Title", text: $model.title)
                if model.canSuggest || !model.snippetDescription.isEmpty {
                    TextField("Description", text: $model.snippetDescription, axis: .vertical).lineLimit(1...3)
                }
                LanguagePicker(selection: model.language, suggestions: model.candidates) { model.pickLanguage($0) }
                CategoryField(categories: $model.categories, known: knownCategories)
            } header: {
                HStack {
                    Text("Details")
                    Spacer()
                    if model.canSuggest {
                        Button { Task { await model.suggest() } } label: {
                            if model.isSuggesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Suggest", symbol: .sparkles)
                            }
                        }
                        .font(.caption)
                        .textCase(nil)
                        .disabled(model.isSuggesting)
                    }
                }
            } footer: {
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Save to ByteCache")
        .task { if model.suggestsOnOpen { await model.suggest() } }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !inlineButtons {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if inlineButtons {
                HStack {
                    Button("Cancel") { onDone(nil) }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    saveButton
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .logScreen("Capture")
    }

    @ViewBuilder
    private var saveButton: some View {
        if model.isSaving {
            ProgressView().controlSize(.small)
        } else {
            Button("Save") {
                Task {
                    if let saved = try? await model.save() {
                        onDone(saved)
                    } else if model.didQueue {
                        onQueued()
                    }
                }
            }
            .disabled(!model.canSave)
            .keyboardShortcut("s", modifiers: .command)
        }
    }
}
