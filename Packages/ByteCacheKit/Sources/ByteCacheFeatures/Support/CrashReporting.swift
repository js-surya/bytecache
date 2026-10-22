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
