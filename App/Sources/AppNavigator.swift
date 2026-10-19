import ByteCatchCore
import Observation

/// Requests to show a snippet, from Spotlight or the Open Snippet intent.
@MainActor @Observable
final class AppNavigator {
    static let shared = AppNavigator()
    var pendingSnippetID: Int?
    /// Set by the Save Clipboard control/shortcut and `bytecatch://capture/clipboard`.
    var pendingClipboardCapture = false

    func handle(_ link: DeepLink) {
        switch link {
        case .snippet(let id): pendingSnippetID = id
        case .captureClipboard: pendingClipboardCapture = true
        case .scanCode: break
        }
    }
}
