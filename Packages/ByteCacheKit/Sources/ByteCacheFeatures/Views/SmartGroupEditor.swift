import ByteCacheCore
import SwiftUI

/// Creates or edits a Smart Group: a name, how rules combine, and the rules.
struct SmartGroupEditor: View {
    @State private var group: SmartGroup
    let isNew: Bool
    let languages: [String]
    let categories: [String]
    let onSave: (SmartGroup) -> Void
    @Environment(\.dismiss) private var dismiss

    init(group: SmartGroup?, languages: [String], categories: [String], onSave: @escaping (SmartGroup) -> Void) {
        _group = State(initialValue: group ?? SmartGroup(name: "", rules: [SmartRule(field: .title)]))
        isNew = group == nil
        self.languages = languages
        self.categories = categories
        self.onSave = onSave
    }

    private var canSave: Bool { !group.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SettingsList {
            Section {
                TextField("Name", text: $group.name)
            }
            Section {
                Picker("Match", selection: $group.match) {
                    ForEach(SmartGroup.Match.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                ForEach($group.rules) { $rule in
                    RuleRow(rule: $rule, languages: languages, categories: categories)
                }
                .onDelete { group.rules.remove(atOffsets: $0) }
                Button {
                    group.rules.append(SmartRule(field: .title))
                } label: {
                    Label("Add Rule", symbol: .plusCircle)
                }
            } header: {
                Text("Rules")
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(isNew ? "New Smart Group" : "Edit Smart Group")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Create" : "Save") {
                    group.name = group.name.trimmingCharacters(in: .whitespaces)
                    onSave(group)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    private var footer: String {
        switch group.match {
        case .all: "Shows snippets that match every rule."
        case .any: "Shows snippets that match at least one rule."
        case .none: "Shows snippets that match none of the rules."
        }
    }
}

private struct RuleRow: View {
    @Binding var rule: SmartRule
    let languages: [String]
    let categories: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Field", selection: $rule.field) {
                    ForEach(SmartRule.Field.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Picker("Condition", selection: $rule.negated) {
                    Text(positive).tag(false)
                    Text(negative).tag(true)
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
            }
            value
        }
        .onChange(of: rule.field) { _, field in
            // A new field starts with a sensible value.
            switch field {
            case .language: rule.value = languages.first ?? ""
            case .tag: rule.value = categories.first ?? ""
            case .modifiedWithinDays: rule.value = "7"
            default: rule.value = ""
            }
        }
    }

    private var positive: String {
        switch rule.field {
        case .title, .description, .code: "contains"
        case .language, .tag: "is"
        case .pinned, .favorite, .modifiedWithinDays: "yes"
        }
    }

    private var negative: String {
        switch rule.field {
        case .title, .description, .code: "doesn't contain"
        case .language, .tag: "is not"
        case .pinned, .favorite, .modifiedWithinDays: "no"
        }
    }

    @ViewBuilder
    private var value: some View {
        switch rule.field {
        case .title, .description, .code:
            TextField("Text", text: $rule.value)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        case .language:
            Picker("Language", selection: $rule.value) {
                ForEach(choices(languages), id: \.self) { Text(LanguageName.display($0)).tag($0) }
            }
        case .tag:
            Picker("Tag", selection: $rule.value) {
                ForEach(choices(categories), id: \.self) { Text($0).tag($0) }
            }
        case .modifiedWithinDays:
            Stepper(value: Binding(get: { Int(rule.value) ?? 7 }, set: { rule.value = String($0) }), in: 1...365) {
                Text("\(Int(rule.value) ?? 7) days")
            }
        case .pinned, .favorite:
            EmptyView()
        }
    }

    /// The library's values, plus the rule's own value if it's no longer in the library.
    private func choices(_ values: [String]) -> [String] {
        rule.value.isEmpty || values.contains(rule.value) ? values : [rule.value] + values
    }
}
