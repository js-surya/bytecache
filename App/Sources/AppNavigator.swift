import Observation

/// Requests to show a snippet, from Spotlight or the Open Snippet intent.
@MainActor @Observable
final class AppNavigator {
    static let shared = AppNavigator()
    var pendingSnippetID: Int?
}
