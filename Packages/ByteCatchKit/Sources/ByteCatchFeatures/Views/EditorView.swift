import ByteCatchCore
import SwiftUI

public struct EditorView: View {
    @Bindable var model: SnippetEditorModel
    let knownCategories: [String]
    let onSaved: (Snippet) -> Void
    let onCancel: () -> Void

    public init(model: SnippetEditorModel, knownCategories: [String], onSaved: @escaping (Snippet) -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        self.knownCategories = knownCategories
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    public var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $model.draft.title)
                TextField("Description", text: $model.draft.description, axis: .vertical)
                    .lineLimit(1...4)
                CategoryField(categories: $model.draft.categories, known: knownCategories)
            }
            ForEach(model.draft.fragments.indices, id: \.self) { index in
                Section {
                    TextField("File name", text: text(index, \.fileName))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onChange(of: model.draft.fragments[safe: index]?.fileName) { model.codeChanged(fragment: index) }
                    LanguagePicker(
                        selection: model.draft.fragments[safe: index]?.language ?? "plaintext",
                        suggestions: model.suggestions[index] ?? []
                    ) { model.setLanguage($0, fragment: index) }
                    TextEditor(text: text(index, \.code))
                        .codeEditorStyle()
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .frame(minHeight: 160)
                        .onChange(of: model.draft.fragments[safe: index]?.code) { model.codeChanged(fragment: index) }
                } header: {
                    HStack {
                        Text(model.draft.fragments.count > 1 ? "File \(index + 1)" : "Code")
                        Spacer()
                        if model.draft.fragments.count > 1 {
                            Button(role: .destructive) { model.removeFragment(at: IndexSet(integer: index)) } label: {
                                Label("Remove File", systemImage: "minus.circle")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            Section {
                Button { model.addFragment() } label: { Label("Add File", systemImage: "plus") }
                Toggle("Public", isOn: $model.draft.isPublic)
            } footer: {
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(model.isNew ? "New Snippet" : "Edit Snippet")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task {
                            if let saved = try? await model.save() { onSaved(saved) }
                        }
                    }
                    .disabled(!model.canSave)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
    }

    /// Bounds-checked binding: a field may briefly outlive its fragment while a removal animates.
    private func text(_ index: Int, _ field: WritableKeyPath<FragmentDraft, String>) -> Binding<String> {
        Binding(
            get: { model.draft.fragments[safe: index]?[keyPath: field] ?? "" },
            set: { if model.draft.fragments.indices.contains(index) { model.draft.fragments[index][keyPath: field] = $0 } }
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
