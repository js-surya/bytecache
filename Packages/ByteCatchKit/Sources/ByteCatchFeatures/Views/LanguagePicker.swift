import ByteCatchLanguage
import SwiftUI

/// "Language" row with a menu of every language, plus the detector's other guesses as one-tap chips.
public struct LanguagePicker: View {
    let selection: String
    let suggestions: [LanguageGuess]
    let onPick: (String) -> Void

    public init(selection: String, suggestions: [LanguageGuess], onPick: @escaping (String) -> Void) {
        self.selection = selection
        self.suggestions = suggestions
        self.onPick = onPick
    }

    private static let sortedIDs = LanguageCatalog.ids.sorted { LanguageName.display($0) < LanguageName.display($1) }

    private var alternatives: [LanguageGuess] {
        Array(suggestions.filter { $0.id != selection }.prefix(3))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Language")
                Spacer()
                Menu {
                    ForEach(Self.sortedIDs, id: \.self) { id in
                        Button { onPick(id) } label: {
                            if id == selection {
                                Label(LanguageName.display(id), symbol: .check)
                            } else {
                                Text(LanguageName.display(id))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(LanguageName.display(selection))
                        Icon(.chevronsUpDown).font(.caption2.weight(.semibold))
                    }
                }
                .fixedSize()
                .accessibilityLabel("Language, \(LanguageName.display(selection))")
            }
            if !alternatives.isEmpty {
                HStack(spacing: 6) {
                    Text("Suggested").font(.caption).foregroundStyle(.secondary)
                    ForEach(alternatives, id: \.id) { guess in
                        Button(LanguageName.display(guess.id)) { onPick(guess.id) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.mini)
                    }
                }
            }
        }
    }
}
