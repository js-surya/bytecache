#if os(macOS)
import AppKit
import ByteCacheFeatures
import Carbon.HIToolbox
import SwiftUI

/// Quick Search as a floating panel over any app, opened by the global shortcut.
@MainActor
final class QuickSearchPanel {
    static let shared = QuickSearchPanel()

    private var panel: NSPanel?
    private var services: AppServices?
    private var resignObserver: NSObjectProtocol?

    /// Called once the app's services exist; (re)registers the shortcut.
    func configure(_ services: AppServices) {
        self.services = services
        GlobalHotKey.shared.action = { [weak self] in self?.toggle() }
        GlobalHotKey.shared.register(services.settings.quickSearchShortcut)
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    private func show() {
        guard let services else { return }
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                             styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.contentView = NSHostingView(rootView:
            QuickSearchView(model: services.quickSearch, lock: services.lock) { [weak self] in self?.close() }
                .appSettingsStyle(services.settings)
        )
        // Upper third of the screen with the mouse, like Spotlight.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 260, y: frame.minY + frame.height * 0.62))
        }
        panel.makeKeyAndOrderFront(nil)
        // Clicking anywhere else closes it.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { QuickSearchPanel.shared.close() }
        }
        self.panel = panel
    }

    func close() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// A non-activating panel normally can't take typing; this one can, so the app you're in stays in front.
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}

/// One system-wide keyboard shortcut (Carbon hot keys work inside the App Sandbox).
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var action: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ shortcut: QuickSearchShortcut) {
        unregister()
        guard let (key, modifiers) = shortcut.carbonKey else { return }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.shared.action?() } }
                return noErr
            }, 1, &event, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4243_5153), id: 1) // "BCQS"
        RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}

private extension QuickSearchShortcut {
    var carbonKey: (UInt32, UInt32)? {
        let space = UInt32(kVK_Space)
        switch self {
        case .off: return nil
        case .controlOptionSpace: return (space, UInt32(controlKey | optionKey))
        case .shiftCommandSpace: return (space, UInt32(shiftKey | cmdKey))
        case .controlOptionCommandSpace: return (space, UInt32(controlKey | optionKey | cmdKey))
        }
    }
}

/// The menu bar window's content; closes the window after copying or opening.
struct MenuBarQuickSearch: View {
    let services: AppServices
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        QuickSearchView(model: services.quickSearch, lock: services.lock) { dismiss() }
            .appSettingsStyle(services.settings)
    }
}
#endif
