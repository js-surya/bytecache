#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

public enum Pasteboard {
    /// Current clipboard text. On iOS this may show the system "Allow Paste" prompt.
    public static func string() -> String? {
        #if canImport(UIKit)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }

    /// Copies and gives feedback (`CopyFeedback`); `toast: false` where the button shows its own "Copied".
    @MainActor
    public static func copy(_ text: String, toast: Bool = true) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        CopyFeedback.copied(toast: toast)
    }
}
