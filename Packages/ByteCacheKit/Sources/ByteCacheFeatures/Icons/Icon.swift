import SwiftUI

extension AppSymbol {
    /// The icon as an `Image` (menus and toolbars need a plain image).
    public func image() -> Image {
        // ByteCache's own {↓} mark is a custom symbol (design/Icons/make-mark.swift).
        self == .byteCache ? Image("bytecache", bundle: .module) : Image(systemName: sfName)
    }
}

/// An app icon: its SF Symbol, which follows the font.
/// Decorative, so hidden from VoiceOver (it would read the symbol name): the surrounding `Label`,
/// button label or `accessibilityLabel` says what it means.
public struct Icon: View {
    let symbol: AppSymbol

    public init(_ symbol: AppSymbol) {
        self.symbol = symbol
    }

    public var body: some View {
        symbol.image()
            .accessibilityHidden(true)
    }
}

extension Label where Title == Text, Icon == ByteCacheFeatures.Icon {
    /// `Label("Pin", symbol: .pin)` — title plus its icon.
    public init(_ title: String, symbol: AppSymbol) {
        self.init { Text(title) } icon: { ByteCacheFeatures.Icon(symbol) }
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, ByteCacheFeatures.Icon>, Description == Text?, Actions == EmptyView {
    /// `ContentUnavailableView("No Snippets", symbol: .tray, description: Text(…))`.
    public init(_ title: String, symbol: AppSymbol, description: Text? = nil) {
        self.init {
            SwiftUI.Label { Text(title) } icon: { ByteCacheFeatures.Icon(symbol) }
        } description: { description }
    }
}
