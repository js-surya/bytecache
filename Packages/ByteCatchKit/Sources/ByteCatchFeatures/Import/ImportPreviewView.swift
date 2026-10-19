import ByteCatchCore
import SwiftUI

/// Pick what to import, then create the snippets.
struct ImportPreviewView: View {
    @State var candidates: [ImportCandidate]
    let session: SessionManager
    let onDone: (String) -> Void
    @State private var working = false

    private var selectedCount: Int { candidates.filter(\.isSelected).count }

    var body: some View {
        List {
            Section {
                ForEach($candidates) { $candidate in
                    Toggle(isOn: $candidate.isSelected) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.title).lineLimit(1)
                            Text(candidate.fragments.map { "\($0.fileName) · \(LanguageName.display($0.language))" }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(selectedCount) of \(candidates.count) selected")
                    Spacer()
                    Button(selectedCount == candidates.count ? "Select None" : "Select All") {
                        let all = selectedCount != candidates.count
                        for i in candidates.indices { candidates[i].isSelected = all }
                    }
                    .font(.caption).textCase(nil)
                }
            }
        }
        .navigationTitle("Import")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone("") } }
            ToolbarItem(placement: .confirmationAction) {
                if working {
                    ProgressView()
                } else {
                    Button("Import \(selectedCount)") {
                        working = true
                        Task {
                            let result = await ImportRunner(session: session).run(candidates)
                            working = false
                            onDone("Imported \(result.created) snippet\(result.created == 1 ? "" : "s")"
                                   + (result.failed > 0 ? ", \(result.failed) failed." : "."))
                        }
                    }
                    .disabled(selectedCount == 0)
                }
            }
        }
    }
}
