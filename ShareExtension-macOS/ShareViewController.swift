import AppKit
import SwiftUI
import ByteCatchFeatures

/// Hosts the capture sheet in the macOS Share menu (plan Task 13).
final class ShareViewController: NSViewController {
    override func loadView() {
        let host = NSHostingView(rootView: SharePlaceholderView { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 320)
        view = host
    }
}
