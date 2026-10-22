import AppIntents
import ByteCacheCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The widget's Copy button: copies a snippet's code without opening the app.
struct CopySnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Snippet"
    static var isDiscoverable: Bool { false }
    /// Copying from a locked iPhone or iPad asks for Face ID or the passcode first.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Snippet")
    var snippetID: Int

    init() {}
    init(snippetID: Int) { self.snippetID = snippetID }

    func perform() async throws -> some IntentResult {
        guard WidgetVisibility.current().allowsCopy, let code = WidgetSnapshotStore().read()?.snippet(id: snippetID)?.code else {
            return .result()
        }
        if let server = AppEnvironment.makeCredentialStore().load()?.server {
            UsageTracker().recordCopy(snippetID: snippetID, server: server)
        }
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
        return .result()
    }
}
