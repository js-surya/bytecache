import ByteCacheCore
import SwiftUI

/// Compact save form shared by the share extensions, clipboard catch and drag and drop.
public struct CaptureSheet: View {
    @Bindable var model: CaptureModel
    let knownCategories: [String]
    let onDone: (Snippet?) -> Void
    let onQueued: () -> Void

    /// `onQueued` runs when the save went to the offline queue instead of the server.
    public init(model: CaptureModel, knownCategories: [String] = [], onQueued: @escaping () -> Void = {},
                onDone: @escaping (Snippet?) -> Void) {
        self.model = model
        self.knownCategories = knownCategories
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
                    Text("Select the code first, then share.").font(.footnote).foregroundStyle(.secondary)
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
        .task { if model.canSuggest { await model.suggest() } }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDone(nil) }
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.isSaving {
                    ProgressView()
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
    }
}
