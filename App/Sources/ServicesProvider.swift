#if os(macOS)
import AppKit

/// Services menu → "Add to ByteCache" (CP-92): select code in any app, choose the service, and
/// ByteCache opens New Snippet with it. Declared in Info.plist (`NSServices`, message
/// `addToByteCache`); the text goes through `AppNavigator` so the main window shows the sheet.
@MainActor
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    func register() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    @objc func addToByteCache(_ pasteboard: NSPasteboard, userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), text.contains(where: { !$0.isWhitespace }) else {
            error.pointee = "Select some code or text first." as NSString
            return
        }
        AppNavigator.shared.pendingCaptureText = text
        NSApp.activate()
        // Menu-bar-only, or every window closed: open the main window, which then shows the sheet.
        if !NSApp.windows.contains(where: { $0.canBecomeMain && $0.isVisible && !($0 is NSPanel) }),
           let url = URL(string: "bytecache://open") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
