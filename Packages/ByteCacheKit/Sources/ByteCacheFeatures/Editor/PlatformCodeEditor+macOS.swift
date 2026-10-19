#if os(macOS)
import AppKit
import SwiftUI

struct PlatformCodeEditor: NSViewRepresentable {
    @Binding var text: String
    let style: EditorStyle

    func makeCoordinator() -> CodeEditorCoordinator {
        CodeEditorCoordinator(text: $text, style: style)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        // TextKit 1: the line-number ruler reads line fragments from the layout manager.
        let storage = NSTextStorage(), layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        // Nothing else owns the storage.
        coordinator.ownedStorage = storage
        let textView = CodeNSTextView(frame: .zero, textContainer: container)
        textView.coordinator = coordinator
        textView.delegate = textView
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        let ruler = LineNumberRuler(scrollView: scroll, coordinator: coordinator)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = style.lineNumbers
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(ruler, selector: #selector(LineNumberRuler.redraw),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)

        coordinator.textView = textView
        coordinator.redrawGutter = { [weak ruler, weak scroll, weak coordinator] in
            guard let ruler, let scroll, let coordinator else { return }
            scroll.rulersVisible = coordinator.style.lineNumbers
            ruler.ruleThickness = coordinator.gutterWidth
            ruler.needsDisplay = true
        }
        coordinator.restyle(style)
        coordinator.load(text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        if coordinator.style != style { coordinator.restyle(style) }
        if coordinator.textView?.string != text { coordinator.load(text) }
    }
}

final class CodeNSTextView: NSTextView, NSTextViewDelegate {
    weak var coordinator: CodeEditorCoordinator?

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString else { return true }
        return coordinator?.shouldChange(range: affectedCharRange, replacement: replacementString) ?? true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let coordinator else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            return !coordinator.shouldChange(range: coordinator.selection, replacement: "\n")
        case #selector(NSResponder.insertTab(_:)):
            return !coordinator.shouldChange(range: coordinator.selection, replacement: "\t")
        case #selector(NSResponder.deleteBackward(_:)):
            return !coordinator.shouldDeleteBackward()
        default:
            return false
        }
    }

    func textDidChange(_ notification: Notification) {
        coordinator?.textChanged()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        coordinator?.selectionChanged()
    }
}

/// Line numbers beside the text, drawn for the visible part only.
final class LineNumberRuler: NSRulerView {
    private weak var coordinator: CodeEditorCoordinator?

    init(scrollView: NSScrollView, coordinator: CodeEditorCoordinator) {
        self.coordinator = coordinator
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = coordinator.gutterWidth
    }

    required init(coder: NSCoder) { fatalError("not used from nibs") }

    @objc func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let coordinator, let textView = coordinator.textView else { return }
        coordinator.style.background.setFill()
        bounds.fill()
        let visible = textView.visibleRect
        let origin = convert(NSPoint(x: 0, y: textView.textContainerOrigin.y), from: textView)
        coordinator.drawLineNumbers(in: rect, visible: visible, originY: origin.y, width: ruleThickness)
    }
}
#endif
