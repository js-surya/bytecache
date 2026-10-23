import ByteCacheCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Starts crash detection and system diagnostics for the app (not the extensions).
@MainActor
public enum CrashReporting {
    /// Call once when the app starts.
    public static func appLaunched() {
        let watch = CrashWatch.shared
        watch.launched()
        AppLog.shared.record("app", "launched ByteCache \(AboutText.versionWithBuild)"
            + (watch.endedUnexpectedly ? "; the last session ended unexpectedly" : ""))
        #if canImport(MetricKit)
        DiagnosticsCollector.shared.start()
        #endif
        #if os(macOS)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            watch.terminated()
        }
        #endif
    }

    /// After a crash: a short toast pointing to Settings → Report a Bug, instead of a prompt that
    /// stops you at launch. The crash waits there until it's reported or dismissed.
    public static func announceUnexpectedEnd() {
        guard CrashWatch.shared.endedUnexpectedly else { return }
        let message = "ByteCache closed unexpectedly. You can report it in Settings → Report a Bug."
        AppLog.shared.record("app", "showed the closed-unexpectedly toast")
        AccessibilityNotification.Announcement(message).post()
        // Long enough to read; gone at the first tap, click or key, so it never stands in the way.
        CopyFeedback.toast.show(message, symbol: .warning, for: .seconds(4), dismissOnInteraction: true)
    }

    /// iPhone and iPad: leaving the foreground is a normal way to end. That starts at "inactive":
    /// swiping ByteCache away in the app switcher ends it there, often before it ever reaches
    /// "background", and that mustn't count as a crash. (A Mac app keeps running with no window in
    /// front, so there only Quit counts.)
    public static func scenePhaseChanged(_ phase: ScenePhase) {
        #if os(iOS)
        switch phase {
        case .active: CrashWatch.shared.enteredForeground()
        case .inactive, .background: CrashWatch.shared.enteredBackground()
        @unknown default: break
        }
        #endif
    }
}
