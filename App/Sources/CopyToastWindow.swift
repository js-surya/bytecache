import SwiftUI
import ByteCacheFeatures

/// Shows `CopyFeedback.toast` in its own click-through window above the active window, so the
/// "Copied" toast is visible above sheets too (a SwiftUI overlay would sit behind them).
@MainActor
enum CopyToastWindow {
    static func install() {
        CopyFeedback.toast.onShow = { duration in show(for: duration) }
    }

    private static var hideTask: Task<Void, Never>?

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
        scheduleHide(after: duration) { window?.isHidden = true }
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
        scheduleHide(after: duration) {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
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
