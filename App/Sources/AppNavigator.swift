import ByteCacheCore
import Observation

/// Requests to show a snippet, from Spotlight or the Open Snippet intent.
@MainActor @Observable
final class AppNavigator {
    static let shared = AppNavigator()
    var pendingSnippetID: Int?
    /// Set by the Save Clipboard control/shortcut and `bytecache://capture/clipboard`.
    var pendingClipboardCapture = false
    var pendingScan = false
    /// Text sent with the Mac's Services menu ("Add to ByteCache") to open in New Snippet.
    var pendingCaptureText: String?

    func handle(_ link: DeepLink) {
        switch link {
        case .snippet(let id): pendingSnippetID = id
        case .captureClipboard: pendingClipboardCapture = true
        case .scanCode: pendingScan = true
        }
    }
}
