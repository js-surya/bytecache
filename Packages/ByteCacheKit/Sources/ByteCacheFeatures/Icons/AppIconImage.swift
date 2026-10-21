import SwiftUI

/// The real app icon (blue gradient, `{ ↓ }`), for the server screen, About and the privacy cover.
/// The image is a flat render of `Design/AppIcon/preview.png`; the system icon itself can't be read.
public struct AppIconImage: View {
    let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Image("about-app-icon", bundle: .module)
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: size / 16, y: size / 32)
            .accessibilityHidden(true)
    }
}
