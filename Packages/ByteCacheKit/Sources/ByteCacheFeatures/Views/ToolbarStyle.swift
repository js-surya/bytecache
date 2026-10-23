import SwiftUI

extension View {
    /// A toolbar button in the label colour, like the system's own (Back, sidebar, "…"), so a bar
    /// doesn't mix accent and plain icons. The accent colour is kept for the one primary action
    /// (`primaryToolbarAction()`) and for colours that mean something (pinned, favourite).
    public func toolbarIcon() -> some View {
        tint(.primary)
    }

    /// The bar's main action (New Snippet): a prominent glass button in the accent colour on
    /// iOS 26 and later, as in Apple's apps (Notes, Mail); a plain tinted icon before.
    @ViewBuilder
    public func primaryToolbarAction() -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
