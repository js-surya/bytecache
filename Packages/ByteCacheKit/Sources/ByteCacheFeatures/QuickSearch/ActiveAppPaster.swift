#if os(macOS)
import AppKit
import ApplicationServices

/// Pastes a snippet into the app the person was using before Quick Search or the menu bar opened
/// (CP-68): it switches back to that app and sends ⌘V. Sending keystrokes to another app needs the
/// Accessibility permission; without it the snippet is only copied.
@MainActor
public final class ActiveAppPaster {
    public static let shared = ActiveAppPaster()

    public enum Outcome: Equatable {
        case pasted
        /// Copied instead: Accessibility isn't allowed yet (the system prompt was shown).
        case copiedNeedsPermission
        /// Copied instead: there's no other app to paste into.
        case copiedNoApp
    }

    private var lastOtherApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    /// Call once at launch: remembers the most recent app that isn't ByteCache.
    public func start() {
        guard observer == nil else { return }
        note(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.note(app) }
        }
    }

    private func note(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastOtherApp = app
    }

    /// Whether ByteCache may send keystrokes (System Settings → Privacy & Security → Accessibility).
    public var isAllowed: Bool { AXIsProcessTrusted() }

    /// Shows the system's "allow ByteCache to control your computer" prompt (only if not allowed yet).
    public func askForPermission() {
        // The value of kAXTrustedCheckOptionPrompt (a C global Swift 6 won't read from here).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Puts the text on the clipboard, then pastes it into the previous app when allowed.
    @discardableResult
    public func paste(_ text: String) -> Outcome {
        Pasteboard.copy(text, toast: false)
        guard isAllowed else {
            askForPermission()
            CopyFeedback.copied("Copied. Allow Accessibility to paste.")
            return .copiedNeedsPermission
        }
        guard let app = lastOtherApp, !app.isTerminated else {
            CopyFeedback.copied()
            return .copiedNoApp
        }
        app.activate()
        Task { @MainActor in
            // Wait (briefly) until that app is in front, so ⌘V lands there and not in ByteCache.
            for _ in 0..<20 where NSWorkspace.shared.frontmostApplication != app {
                try? await Task.sleep(for: .milliseconds(25))
            }
            try? await Task.sleep(for: .milliseconds(60))
            Self.pressCommandV()
        }
        return .pasted
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 0x09 // kVK_ANSI_V
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
#endif
