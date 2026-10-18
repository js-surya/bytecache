import ByteCatchLanguage
import SwiftUI

/// Detector suggestions as one-tap chips, plus the full catalog.
public struct LanguagePicker: View {
    let selection: String
    let suggestions: [LanguageGuess]
    let onPick: (String) -> Void

    public init(selection: String, suggestions: [LanguageGuess], onPick: @escaping (String) -> Void) {
        self.selection = selection
        self.suggestions = suggestions
        self.onPick = onPick
    }

    public var body: some View {
        HStack {
            Menu {
                ForEach(LanguageCatalog.ids.sorted { LanguageName.display($0) < LanguageName.display($1) }, id: \.self) { id in
                    Button { onPick(id) } label: {
                        if id == selection { Label(LanguageName.display(id), systemImage: "checkmark") } else { Text(LanguageName.display(id)) }
                    }
                }
            } label: {
                Label(LanguageName.display(selection), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .fixedSize()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions.filter { $0.id != selection }, id: \.id) { guess in
                        Button(LanguageName.display(guess.id)) { onPick(guess.id) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}
