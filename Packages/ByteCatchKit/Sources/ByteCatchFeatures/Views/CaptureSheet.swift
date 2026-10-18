import ByteCatchCore
import SwiftUI

/// Compact save form shared by the share extensions, clipboard catch and drag and drop.
public struct CaptureSheet: View {
    @Bindable var model: CaptureModel
    let knownCategories: [String]
    let onDone: (Snippet?) -> Void

    public init(model: CaptureModel, knownCategories: [String] = [], onDone: @escaping (Snippet?) -> Void) {
        self.model = model
        self.knownCategories = knownCategories
        self.onDone = onDone
    }

    public var body: some View {
        Form {
            if model.signedOut {
                Section {
                    Label(CaptureModel.signInMessage, systemImage: "person.crop.circle.badge.exclamationmark")
                    Button { Pasteboard.copy(model.text) } label: { Label("Copy Code", systemImage: "doc.on.doc") }
                }
            }
            Section("Code") {
                TextEditor(text: $model.text)
                    .codeEditorStyle()
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .frame(minHeight: 120, maxHeight: 220)
                    .onChange(of: model.text) { model.textChanged() }
                if !model.text.contains(where: { !$0.isWhitespace }) {
                    Text("Select the code first, then share.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("Title", text: $model.title)
                LanguagePicker(selection: model.language, suggestions: model.candidates) { model.pickLanguage($0) }
                CategoryField(categories: $model.categories, known: knownCategories)
            } header: {
                Text("Details")
            } footer: {
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Save to ByteCatch")
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
                        Task { if let saved = try? await model.save() { onDone(saved) } }
                    }
                    .disabled(!model.canSave)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
    }
}
