import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Offers to save copied text. Only checks *whether* text is on the clipboard (no read, no prompt);
/// the text is read through `PasteButton`, i.e. only when the user taps it.
@MainActor @Observable
public final class ClipboardWatcher {
    public private(set) var hasText = false
    @ObservationIgnored private var dismissedChange = -1

    public init() {}

    private var changeCount: Int {
        #if canImport(UIKit)
        UIPasteboard.general.changeCount
        #else
        NSPasteboard.general.changeCount
        #endif
    }

    public func check() {
        #if canImport(UIKit)
        let available = UIPasteboard.general.hasStrings
        #else
        let available = NSPasteboard.general.availableType(from: [.string]) != nil
        #endif
        hasText = available && changeCount != dismissedChange
    }

    public func dismiss() {
        dismissedChange = changeCount
        hasText = false
    }
}

public struct ClipboardBanner: View {
    let watcher: ClipboardWatcher
    let onPaste: (String) -> Void

    public init(watcher: ClipboardWatcher, onPaste: @escaping (String) -> Void) {
        self.watcher = watcher
        self.onPaste = onPaste
    }

    public var body: some View {
        HStack {
            Image(systemName: "doc.on.clipboard")
            Text("Save copied code?").font(.subheadline)
            Spacer()
            PasteButton(payloadType: String.self) { strings in
                let text = strings.joined(separator: "\n")
                Task { @MainActor in
                    watcher.dismiss()
                    onPaste(text)
                }
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            Button { watcher.dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
