import SwiftUI

extension View {
    /// The background of a floating control (the Select bar, the "Copied" toast, the clipboard banner):
    /// Liquid Glass on iOS 26 / macOS 26 and later, so it matches the system's bars; the regular
    /// material before (CP-102). For controls only: content such as cards keeps its own background.
    @ViewBuilder
    public func glassSurface(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
