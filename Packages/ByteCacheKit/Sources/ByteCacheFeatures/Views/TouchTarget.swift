import SwiftUI

extension View {
    /// Small controls on the touchscreen Mac (CP-95): Apple asks for at least 36 points each way for a
    /// finger. The control keeps its size and look; only the area that responds grows, so pointer
    /// layout is unchanged. iPhone and iPad lay these out for touch already.
    public func touchTarget() -> some View {
        #if os(macOS)
        contentShape(.interaction, Rectangle().inset(by: -7))
        #else
        self
        #endif
    }
}
