import SwiftUI

extension View {
    /// Centres the view in the largest part of its space that no fold crosses. On iPhone Duo, partially
    /// folded (laptop or book), a view centred on the whole screen would sit on the hinge (CP-83).
    /// Elsewhere it's plain centring.
    public func centeredAwayFromFold() -> some View {
        modifier(FoldAvoidingCenter())
    }
}

struct FoldAvoidingCenter: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let area = Self.area(in: proxy)
            content
                .frame(width: area.width, height: area.height)
                .position(x: area.midX, y: area.midY)
        }
    }

    private static func area(in proxy: GeometryProxy) -> CGRect {
        let bounds = CGRect(origin: .zero, size: proxy.size)
        // Reserved regions need the Xcode 27.1 SDK (Swift 6.4); Xcode 26 builds centre plainly.
        #if os(iOS) && compiler(>=6.4)
        guard #available(iOS 27.1, *) else { return bounds }
        let folds = proxy.reservedRegions(kind: .division).filter { $0.isActive }.map { $0.frame }
        return largestPart(of: bounds, avoiding: folds)
        #else
        return bounds
        #endif
    }

    /// The biggest rectangle of `bounds` left after cutting out every fold. When parts are about the
    /// same size, the top (or leading) one: in laptop pose that's the half facing the user.
    nonisolated static func largestPart(of bounds: CGRect, avoiding folds: [CGRect]) -> CGRect {
        var parts = [bounds]
        for fold in folds {
            parts = parts.flatMap { part -> [CGRect] in
                let cut = part.intersection(fold)
                guard !cut.isNull, !cut.isEmpty else { return [part] }
                return [
                    CGRect(x: part.minX, y: part.minY, width: part.width, height: cut.minY - part.minY),
                    CGRect(x: part.minX, y: cut.maxY, width: part.width, height: part.maxY - cut.maxY),
                    CGRect(x: part.minX, y: part.minY, width: cut.minX - part.minX, height: part.height),
                    CGRect(x: cut.maxX, y: part.minY, width: part.maxX - cut.maxX, height: part.height),
                ].filter { $0.width > 0 && $0.height > 0 }
            }
        }
        let biggest = parts.map { $0.width * $0.height }.max() ?? 0
        return parts.first { $0.width * $0.height >= biggest * 0.85 } ?? bounds
    }
}
