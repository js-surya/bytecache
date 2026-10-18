import SwiftUI

/// Category chips with remove buttons and a field that adds on Return or comma.
public struct CategoryField: View {
    @Binding var categories: [String]
    let known: [String]
    @State private var text = ""

    public init(categories: Binding<[String]>, known: [String]) {
        _categories = categories
        self.known = known
    }

    private var matches: [String] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return known.filter { $0.lowercased().hasPrefix(query) && !categories.contains($0) }.prefix(5).map { $0 }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(categories, id: \.self) { category in
                            Button {
                                categories.removeAll { $0 == category }
                            } label: {
                                Label(category, systemImage: "xmark.circle.fill").labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Remove \(category)")
                        }
                    }
                }
            }
            TextField("Add category", text: $text)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit(commit)
                .onChange(of: text) { if text.contains(",") { commit() } }
            if !matches.isEmpty {
                HStack {
                    ForEach(matches, id: \.self) { match in
                        Button(match) { add(match) }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
    }

    private func commit() {
        text.split(separator: ",").forEach { add(String($0)) }
        text = ""
    }

    private func add(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if !name.isEmpty, !categories.contains(name) { categories.append(name) }
        text = ""
    }
}
