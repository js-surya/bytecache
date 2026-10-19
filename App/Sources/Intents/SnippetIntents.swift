import AppIntents
import ByteCatchCore
import ByteCatchFeatures
import ByteCatchLanguage

struct IntentMessage: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

struct SaveToByteCatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to ByteCatch"
    static let description = IntentDescription("Saves text as a new snippet on your ByteStash server. The language is detected automatically.")

    @Parameter(title: "Code", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Title")
    var snippetTitle: String?

    @Parameter(title: "Language", description: "A ByteStash language id such as python or bash.")
    var language: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text) to ByteCatch") {
            \.$snippetTitle
            \.$language
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            let snippet = try await IntentActions.save(
                text: text, title: snippetTitle, language: language,
                store: AppEnvironment.makeCredentialStore(), detector: LanguageDetector(), queue: .shared
            )
            return .result(value: snippet.title, dialog: "Saved “\(snippet.title)”.")
        } catch {
            throw IntentMessage(message: error.message)
        }
    }
}

struct SearchSnippetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Snippets"
    static let description = IntentDescription("Finds snippets on your ByteStash server, or in recently viewed ones when offline.")

    @Parameter(title: "Search")
    var term: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[SnippetEntity]> {
        let found = await IntentActions.search(term, store: AppEnvironment.makeCredentialStore(), cache: try? SnippetCache())
        return .result(value: found.map(SnippetEntity.init))
    }
}

struct OpenSnippetIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Snippet"

    @Parameter(title: "Snippet")
    var target: SnippetEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.pendingSnippetID = target.id
        return .result()
    }
}

struct ByteCatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveToByteCatchIntent(),
            phrases: ["Save to \(.applicationName)", "Save code to \(.applicationName)"],
            shortTitle: "Save Snippet",
            systemImageName: "square.and.arrow.down"
        )
        AppShortcut(
            intent: SaveClipboardIntent(),
            phrases: ["Save clipboard to \(.applicationName)", "Catch copied code with \(.applicationName)"],
            shortTitle: "Save Clipboard",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: ScanCodeIntent(),
            phrases: ["Scan code with \(.applicationName)"],
            shortTitle: "Scan Code",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: SearchSnippetsIntent(),
            phrases: ["Search \(.applicationName)", "Find a snippet in \(.applicationName)"],
            shortTitle: "Search Snippets",
            systemImageName: "magnifyingglass"
        )
    }
}
