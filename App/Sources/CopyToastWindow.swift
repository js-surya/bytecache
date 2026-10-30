import SwiftUI
import ByteCacheFeatures
#if os(iOS)
import UIKit.UIGestureRecognizerSubclass
#endif

/// Shows `CopyFeedback.toast` in its own click-through window above the active window, so the
/// "Copied" toast is visible above sheets too (a SwiftUI overlay would sit behind them).
@MainActor
enum CopyToastWindow {
    static func install() {
        CopyFeedback.toast.onShow = { duration in show(for: duration) }
    }

    private static var hideTask: Task<Void, Never>?

    /// The person started using the app: a toast that goes on interaction goes now.
    private static func interacted() {
        stopWatchingInteraction()
        guard CopyFeedback.toast.dismissesOnInteraction else { return }
        CopyFeedback.toast.hide()
        // Let it animate out before the window goes.
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            hideWindow()
        }
    }

    /// Hides the window once the toast has animated out (it stays as long as the toast does).
    private static func scheduleHide(after duration: Duration, _ hide: @escaping @MainActor () -> Void) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: duration + .seconds(0.6))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    #if os(iOS)
    private static var window: UIWindow?

    private static func show(for duration: Duration) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        if window?.windowScene !== scene {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.backgroundColor = .clear
            window.isUserInteractionEnabled = false
            // Top: clear of the tab bar, the clipboard banner and the keyboard.
            let host = UIHostingController(rootView: CopyToastLayer(model: CopyFeedback.toast, edge: .top))
            host.view.backgroundColor = .clear
            window.rootViewController = host
            self.window = window
        }
        window?.isHidden = false
        scheduleHide(after: duration) { hideWindow() }
        stopWatchingInteraction()
        if CopyFeedback.toast.dismissesOnInteraction {
            // On the app's own windows (the toast's ignores touches); the touch still does its job.
            for appWindow in scene.windows where appWindow !== window {
                let watcher = FirstTouch { interacted() }
                appWindow.addGestureRecognizer(watcher)
                watchers.append(watcher)
            }
        }
    }

    private static func hideWindow() {
        window?.isHidden = true
        stopWatchingInteraction()
    }

    private static var watchers: [FirstTouch] = []

    private static func stopWatchingInteraction() {
        for watcher in watchers { watcher.view?.removeGestureRecognizer(watcher) }
        watchers = []
    }

    /// Notices the first touch anywhere in a window without taking it from the app.
    private final class FirstTouch: UIGestureRecognizer {
        private let onTouch: () -> Void

        init(_ onTouch: @escaping () -> Void) {
            self.onTouch = onTouch
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            state = .failed
            onTouch()
        }
    }
    #elseif os(macOS)
    private static var panel: NSPanel?

    private static func show(for duration: Duration) {
        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        // Room for longer messages (two lines), never wider than the window.
        let long = (CopyFeedback.toast.message?.count ?? 0) > 30
        let size = NSSize(width: min(long ? 460 : 260, parent.frame.width - 40), height: long ? 110 : 90)
        let frame = parent.frame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 8,
                              width: size.width, height: size.height), display: false)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        scheduleHide(after: duration) { hideWindow() }
        stopWatchingInteraction()
        if CopyFeedback.toast.dismissesOnInteraction {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { event in
                MainActor.assumeIsolated { interacted() }
                return event
            }
            // Touches on the touchscreen Mac never reach event monitors (CP-95); a recognizer sees them.
            let watcher = TouchWatcher { interacted() }
            parent.contentView?.addGestureRecognizer(watcher)
            touchWatcher = watcher
        }
    }

    private static var monitor: Any?

    private static func hideWindow() {
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        stopWatchingInteraction()
    }

    private static func stopWatchingInteraction() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let touchWatcher { touchWatcher.view?.removeGestureRecognizer(touchWatcher) }
        touchWatcher = nil
    }

    private static var touchWatcher: TouchWatcher?

    /// Notices a finger touching the window and fails at once, so it never takes a touch from the
    /// controls underneath.
    final class TouchWatcher: NSGestureRecognizer {
        private let onTouch: @MainActor () -> Void

        init(onTouch: @escaping @MainActor () -> Void) {
            self.onTouch = onTouch
            super.init(target: nil, action: nil)
            allowedTouchTypes = .direct
            delaysPrimaryMouseButtonEvents = false
        }

        required init?(coder: NSCoder) { nil }

        override func touchesBegan(with event: NSEvent) {
            onTouch()
            state = .failed
        }

        override func location(in view: NSView?) -> NSPoint { .zero }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: CopyToastLayer(model: CopyFeedback.toast))
        return panel
    }
    #endif
}
