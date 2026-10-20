import AppIntents
import ByteCacheCore
import ByteCacheFeatures
import ByteCacheLanguage

struct IntentMessage: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

struct SaveToByteCacheIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to ByteCache"
    static let description = IntentDescription("Saves text as a new snippet on your ByteStash server. The language is detected automatically.")

    @Parameter(title: "Code", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Title")
    var snippetTitle: String?

    @Parameter(title: "Language", description: "A ByteStash language id such as python or bash.")
    var language: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text) to ByteCache") {
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

/// Kept under its original type name so existing shortcuts keep working.
struct SearchSnippetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Snippets"
    static let description = IntentDescription(
        "Finds snippets on your ByteStash server (or saved ones when offline). Each result has a Title, Language, Code and Tags to use in later steps. The search can include filters like lang:python or #tag."
    )

    @Parameter(title: "Search", default: "")
    var term: String

    @Parameter(title: "Language", description: "A language such as python or bash.")
    var language: String?

    @Parameter(title: "Tag")
    var tag: String?

    @Parameter(title: "Limit", default: 20, inclusiveRange: (1, 100))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Find snippets matching \(\.$term)") {
            \.$language
            \.$tag
            \.$limit
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[SnippetEntity]> {
        do {
            let found = try await IntentActions.find(term, language: language, tag: tag, limit: limit,
                                                     store: AppEnvironment.makeCredentialStore(), cache: try? SnippetCache())
            return .result(value: found.map(SnippetEntity.init))
        } catch {
            throw IntentMessage(message: error.message)
        }
    }
}

struct GetSnippetCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Snippet Code"
    static let description = IntentDescription("Gets a snippet's code as text, to use in later steps of a shortcut.")

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    @Parameter(title: "All Files", description: "Off: only the first file.", default: true)
    var allFiles: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Get the code of \(\.$snippet)") {
            \.$allFiles
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let code = try await IntentActions.code(ofSnippet: snippet.id, allFiles: allFiles,
                                                    store: AppEnvironment.makeCredentialStore(), cache: try? SnippetCache())
            return .result(value: code)
        } catch {
            throw IntentMessage(message: error.message)
        }
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

struct ByteCacheShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveToByteCacheIntent(),
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
            shortTitle: "Find Snippets",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: GetSnippetCodeIntent(),
            phrases: ["Get code from \(.applicationName)", "Get a snippet from \(.applicationName)"],
            shortTitle: "Get Snippet Code",
            systemImageName: "chevron.left.forwardslash.chevron.right"
        )
    }
}
