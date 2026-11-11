import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension AppSymbol {
    /// The icon as an `Image` (menus and toolbars need a plain image).
    public func image() -> Image {
        // ByteCache's own {↓} mark is a custom symbol (design/Icons/make-mark.swift).
        if self == .byteCache { return Image("bytecache", bundle: .module) }
        #if canImport(UIKit)
        // The flip is part of the image, so toolbars and menus (which take just the image) keep it.
        if isMirrored, let flipped = Self.drawnMirrored(sfName) {
            return Image(uiImage: flipped)
        }
        #endif
        return Image(systemName: sfName)
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
            #if !canImport(UIKit)
            .scaleEffect(x: symbol.isMirrored ? -1 : 1, y: 1)
            #endif
            .accessibilityHidden(true)
    }
}

#if canImport(UIKit)
extension AppSymbol {
    /// The symbol drawn flipped into a new template image. Toolbars look a symbol up again by name,
    /// which drops a flipped orientation or a scale effect, so the flip has to be in the pixels.
    static func drawnMirrored(_ name: String) -> UIImage? {
        let config = UIImage.SymbolConfiguration(textStyle: .body, scale: .large).applying(UIImage.SymbolConfiguration(weight: .medium))
        guard let symbol = UIImage(systemName: name, withConfiguration: config) else { return nil }
        let size = symbol.size
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.translateBy(x: size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            symbol.draw(in: CGRect(origin: .zero, size: size))
        }
        .withRenderingMode(.alwaysTemplate)
        .withBaselineOffset(fromBottom: symbol.baselineOffsetFromBottom ?? 0)
    }
}
#endif

extension AppSymbol {
    /// Drawn right to left: Wrap Long Lines is `text.append` with its arrow coming back to the start
    /// of the next line, like wrapped text.
    var isMirrored: Bool { self == .wrapLines }
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
