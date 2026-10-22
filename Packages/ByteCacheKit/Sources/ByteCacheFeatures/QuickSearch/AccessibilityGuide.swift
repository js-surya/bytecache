#if os(macOS)
import AppKit
import ApplicationServices
import SwiftUI

/// Helps allow Accessibility (for Paste into Active App): opens System Settings → Privacy & Security →
/// Accessibility and floats a small panel under its window with ByteCache's icon, which you drag into
/// the list. The panel follows the window and closes itself once access is allowed.
@MainActor
public final class AccessibilityGuide {
    public static let shared = AccessibilityGuide()

    private var panel: NSPanel?
    private var watcher: Task<Void, Never>?
    private static let panelSize = NSSize(width: 360, height: 128)

    public func show() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, let panel = self.panel else { return }
                if AXIsProcessTrusted() {
                    self.close()
                    CopyFeedback.copied("Paste into Active App is ready")
                    return
                }
                // System Settings was closed: nothing to drag into any more.
                if self.settingsWindowFrame() == nil, panel.isVisible, Self.settingsApp == nil {
                    self.close()
                    return
                }
                self.place(panel)
            }
        }
    }

    public func close() {
        watcher?.cancel()
        watcher = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: GuideView { [weak self] in self?.close() })
        return panel
    }

    /// Under the System Settings window (or over its bottom edge when the screen has no room below).
    private func place(_ panel: NSPanel) {
        let size = Self.panelSize
        guard let window = settingsWindowFrame() else {
            if !panel.isVisible { panel.center() }
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(window) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? window
        var origin = NSPoint(x: window.midX - size.width / 2, y: window.minY - size.height - 10)
        if origin.y < visible.minY { origin.y = window.minY + 16 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private static var settingsApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
    }

    /// The System Settings window in AppKit coordinates. Window bounds don't need Screen Recording.
    private func settingsWindowFrame() -> NSRect? {
        guard let app = Self.settingsApp,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for info in windows {
            guard info[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 200 else { continue }
            // CG counts from the top of the main screen, AppKit from its bottom.
            let mainHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
            return NSRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        return nil
    }
}

private struct GuideView: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                .help("Drag into the Accessibility list")
            VStack(alignment: .leading, spacing: 4) {
                Text("Drag ByteCache into the list above")
                    .font(.headline)
                Text("Then turn it on. This lets ByteCache press ⌘V in the app you were using.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .frame(width: 360, height: 128)
    }
}
#endif
