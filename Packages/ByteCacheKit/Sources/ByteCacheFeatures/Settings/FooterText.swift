import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A section note justified edge to edge, in the footnote style. SwiftUI's Text can't justify, so
/// this wraps a label; light hyphenation keeps the gaps between words even on narrow screens.
public struct FooterText: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        JustifiedLabel(text: text)
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}

/// A section note that stays out of the way: a small ⓘ that shows the text in a popover when tapped.
/// For explanations people can live without; warnings, consent and steps they need stay `FooterText`.
public struct InfoFooter: View {
    let text: String
    @State private var showing = false

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Button { showing = true } label: {
            Icon(.infoCircle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More Info")
        .accessibilityHint(text)
        .help(text)
        .popover(isPresented: $showing, arrowEdge: .top) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300, alignment: .leading)
                .padding(16)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private func justifiedString(_ text: String, font: Any, color: Any) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .justified
    paragraph.hyphenationFactor = 0.6
    #if canImport(UIKit)
    return NSAttributedString(string: text, attributes: [.font: font as! UIFont, .foregroundColor: color as! UIColor, .paragraphStyle: paragraph])
    #else
    return NSAttributedString(string: text, attributes: [.font: font as! NSFont, .foregroundColor: color as! NSColor, .paragraphStyle: paragraph])
    #endif
}

#if canImport(UIKit)
private struct JustifiedLabel: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = justifiedString(text, font: UIFont.preferredFont(forTextStyle: .footnote), color: UIColor.secondaryLabel)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? label.window?.bounds.width ?? label.bounds.width
        let size = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }
}
#else
private struct JustifiedLabel: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.isSelectable = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        label.attributedStringValue = justifiedString(text, font: NSFont.preferredFont(forTextStyle: .footnote), color: NSColor.secondaryLabelColor)
    }

    // Measures without changing the label: AppKit stops the app if a view changes during layout.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView label: NSTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)) ?? .zero
        return CGSize(width: width, height: ceil(size.height))
    }
}
#endif
