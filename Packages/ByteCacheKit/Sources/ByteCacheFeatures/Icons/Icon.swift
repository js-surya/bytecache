import SwiftUI

extension EnvironmentValues {
    /// SF Symbols or Lucide, from Settings → Appearance.
    @Entry public var iconStyle: IconStyle = .sfSymbols
}

extension AppSymbol {
    /// The icon as an `Image` (menus and toolbars need a plain image).
    public func image(_ style: IconStyle) -> Image {
        switch style {
        case .sfSymbols: Image(systemName: sfName)
        case .lucide: Image(lucideAsset, bundle: .module).renderingMode(.template)
        }
    }
}

/// An app icon in the user's chosen style. `size` pins a Lucide icon's size; SF Symbols follow the font.
/// Decorative, so hidden from VoiceOver (it would read the asset name): the surrounding `Label`,
/// button label or `accessibilityLabel` says what it means.
public struct Icon: View {
    let symbol: AppSymbol
    let size: CGFloat?
    @Environment(\.iconStyle) private var style

    public init(_ symbol: AppSymbol, size: CGFloat? = nil) {
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        Group {
            if style == .lucide, let size {
                symbol.image(style).resizable().scaledToFit().frame(width: size, height: size)
            } else {
                symbol.image(style)
            }
        }
        .accessibilityHidden(true)
    }
}

extension Label where Title == Text, Icon == ByteCacheFeatures.Icon {
    /// `Label("Pin", symbol: .pin)` — title plus an icon in the chosen style.
    public init(_ title: String, symbol: AppSymbol) {
        self.init { Text(title) } icon: { ByteCacheFeatures.Icon(symbol) }
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, ByteCacheFeatures.Icon>, Description == Text?, Actions == EmptyView {
    /// `ContentUnavailableView("No Snippets", symbol: .tray, description: Text(…))` in the chosen icon style.
    public init(_ title: String, symbol: AppSymbol, description: Text? = nil) {
        self.init {
            SwiftUI.Label { Text(title) } icon: { ByteCacheFeatures.Icon(symbol, size: 48) }
        } description: { description }
    }
}
