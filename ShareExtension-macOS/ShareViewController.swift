import AppKit
import SwiftUI
import ByteCatchFeatures

/// Hosts the share flow in the macOS Share menu.
final class ShareViewController: NSViewController {
    override func loadView() {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let host = NSHostingView(rootView: ShareFlowView(items: items) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 560)
        view = host
    }
}
