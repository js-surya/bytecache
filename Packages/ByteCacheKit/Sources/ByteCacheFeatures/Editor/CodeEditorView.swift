import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformTextView = UITextView
typealias EditorColor = UIColor
typealias EditorFont = UIFont
#else
import AppKit
typealias PlatformTextView = NSTextView
typealias EditorColor = NSColor
typealias EditorFont = NSFont
#endif

/// Code editor with live syntax colouring, line numbers, auto-indent, auto-closing brackets,
/// matching-bracket highlight and find & replace. UITextView on iPhone/iPad, NSTextView on Mac.
public struct CodeEditorView: View {
    @Binding var text: String
    let language: String
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    public init(text: Binding<String>, language: String) {
        _text = text
        self.language = language
    }

    public var body: some View {
        let palette = settings.codeTheme.palette(for: colorScheme)
        PlatformCodeEditor(text: $text, style: EditorStyle(
            language: language, palette: palette, fontSize: settings.codeFontSize, lineNumbers: settings.showLineNumbers
        ))
        .background(CodeTheme.color(palette.background), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct EditorStyle: Equatable {
    var language: String
    var palette: CodeTheme.Palette
    var fontSize: Double
    var lineNumbers: Bool

    var font: EditorFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    var foreground: EditorColor { .editorHex(palette.foreground) }
    var background: EditorColor { .editorHex(palette.background) }
}

extension EditorColor {
    static func editorHex(_ hex: String) -> EditorColor {
        let rgb = CodeTheme.rgb(hex) ?? (0.5, 0.5, 0.5)
        return EditorColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
}

/// Text handling shared by both platforms: key behaviour, colouring and bracket matching.
@MainActor
final class CodeEditorCoordinator: NSObject {
    var text: Binding<String>
    var style: EditorStyle
    weak var textView: PlatformTextView?
    /// Keeps the hand-built TextKit 1 stack alive.
    var ownedStorage: NSTextStorage?
    /// Called after the text or layout changes so the line numbers redraw.
    var redrawGutter: () -> Void = {}
    private(set) var lineStarts: [Int] = [0]
    private let highlighter = EditorHighlighter()
    private var highlightTask: Task<Void, Never>?
    private var applying = false
    private var indentUnit = "    "

    init(text: Binding<String>, style: EditorStyle) {
        self.text = text
        self.style = style
    }

    var storage: NSTextStorage? { textView?.textStorage }

    var selection: NSRange {
        #if canImport(UIKit)
        textView?.selectedRange ?? NSRange()
        #else
        textView?.selectedRange() ?? NSRange()
        #endif
    }

    // MARK: Text in and out

    /// Loads text from SwiftUI (first show, or a change made outside the editor).
    func load(_ newText: String) {
        guard let textView, let storage else { return }
        storage.setAttributedString(NSAttributedString(string: newText, attributes: baseAttributes))
        textView.typingAttributes = baseAttributes
        textChanged(sync: false)
    }

    func restyle(_ newStyle: EditorStyle) {
        let languageChanged = newStyle.language != style.language
        style = newStyle
        guard let textView, let storage else { return }
        textView.backgroundColor = style.background
        #if canImport(UIKit)
        textView.tintColor = .tintColor
        textView.typingAttributes = baseAttributes
        #else
        textView.insertionPointColor = style.foreground
        textView.typingAttributes = baseAttributes
        #endif
        storage.addAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        if languageChanged { highlightTask?.cancel() }
        scheduleHighlight(after: .zero)
        redrawGutter()
    }

    func textChanged(sync: Bool = true) {
        guard let textView else { return }
        let current = textView.string
        if sync, text.wrappedValue != current { text.wrappedValue = current }
        lineStarts = CodeEditing.lineStarts(in: current)
        indentUnit = CodeEditing.indentUnit(for: current)
        scheduleHighlight(after: .milliseconds(250))
        selectionChanged()
        redrawGutter()
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: style.font, .foregroundColor: style.foreground]
    }

    // MARK: Keys

    /// Decides what a text change becomes. Returns false when the coordinator applied its own edit.
    func shouldChange(range: NSRange, replacement: String) -> Bool {
        guard !applying, !hasMarkedText, let current = textView?.string else { return true }
        let selected = selection
        // UIKit reports backspace as replacing the character before the caret.
        if replacement.isEmpty, range.length == 1, selected.length == 0, range.location == selected.location - 1 {
            return shouldDeleteBackward()
        }
        // Only react to typing at the caret/selection, not to paste or autocorrect elsewhere.
        guard range == selected else { return true }
        let edit: TextEdit?
        switch replacement {
        case "\n":
            edit = CodeEditing.newline(in: current, selection: range, indentUnit: indentUnit)
        case "\t" where indentUnit != "\t":
            edit = TextEdit(range: range, replacement: indentUnit,
                            selection: NSRange(location: range.location + (indentUnit as NSString).length, length: 0))
        default:
            edit = CodeEditing.insert(replacement, in: current, selection: range)
        }
        guard let edit else { return true }
        apply(edit)
        return false
    }

    /// Backspace with an empty selection.
    func shouldDeleteBackward() -> Bool {
        guard !applying, !hasMarkedText, let current = textView?.string,
              let edit = CodeEditing.deleteBackward(in: current, selection: selection) else { return true }
        apply(edit)
        return false
    }

    /// Typed from the keyboard accessory bar.
    func type(_ string: String) {
        if shouldChange(range: selection, replacement: string) {
            apply(TextEdit(range: selection, replacement: string,
                           selection: NSRange(location: selection.location + (string as NSString).length, length: 0)))
        }
    }

    func apply(_ edit: TextEdit) {
        guard let textView else { return }
        applying = true
        defer { applying = false }
        if edit.range.length > 0 || !edit.replacement.isEmpty {
            #if canImport(UIKit)
            if let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
               let end = textView.position(from: start, offset: edit.range.length),
               let range = textView.textRange(from: start, to: end) {
                textView.replace(range, withText: edit.replacement)
            }
            #else
            textView.insertText(edit.replacement, replacementRange: edit.range)
            #endif
        }
        #if canImport(UIKit)
        textView.selectedRange = edit.selection
        #else
        textView.setSelectedRange(edit.selection)
        #endif
        textChanged()
    }

    private var hasMarkedText: Bool {
        #if canImport(UIKit)
        textView?.markedTextRange != nil
        #else
        textView?.hasMarkedText() ?? false
        #endif
    }

    // MARK: Colour

    private func scheduleHighlight(after delay: Duration) {
        highlightTask?.cancel()
        let snapshot = textView?.string ?? ""
        let style = style
        highlightTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            let runs = await self.highlighter.runs(for: snapshot, language: style.language, palette: style.palette)
            guard !Task.isCancelled, let storage = self.storage, storage.string == snapshot else { return }
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: style.foreground, range: NSRange(location: 0, length: storage.length))
            for run in runs ?? [] where NSMaxRange(run.range) <= storage.length {
                storage.addAttribute(.foregroundColor, value: EditorColor.editorHex(run.hex), range: run.range)
            }
            storage.endEditing()
        }
    }

    // MARK: Matching bracket

    func selectionChanged() {
        guard let storage, let current = textView?.string else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: full)
        let selected = selection
        if selected.length == 0, let pair = CodeEditing.matchingBracket(in: current, caret: selected.location) {
            let mark = style.foreground.withAlphaComponent(0.22)
            for location in [pair.bracket, pair.match] where location < storage.length {
                storage.addAttribute(.backgroundColor, value: mark, range: NSRange(location: location, length: 1))
            }
        }
        storage.endEditing()
    }

    // MARK: Line numbers

    /// 1-based line number for a character offset that starts a line, else nil.
    func lineNumber(startingAt offset: Int) -> Int? {
        var low = 0, high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] == offset { return mid + 1 }
            if lineStarts[mid] < offset { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    var gutterWidth: CGFloat {
        guard style.lineNumbers else { return 0 }
        let digits = max(String(lineStarts.count).count, 2)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: gutterFont]).width
        return ceil(CGFloat(digits) * digitWidth + 16)
    }

    var gutterFont: EditorFont { .monospacedDigitSystemFont(ofSize: max(style.fontSize - 2, 9), weight: .regular) }
    var gutterColor: EditorColor { style.foreground.withAlphaComponent(0.4) }

    /// Draws the numbers for the visible line fragments. `originY` maps text-container y to drawing y.
    func drawLineNumbers(in rect: CGRect, visible: CGRect, originY: CGFloat, width: CGFloat) {
        #if canImport(UIKit)
        guard let textView else { return }
        let layoutManager = textView.layoutManager, container = textView.textContainer
        #else
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        #endif
        let attributes: [NSAttributedString.Key: Any] = [.font: gutterFont, .foregroundColor: gutterColor]
        let lineHeight = style.font.editorLineHeight
        func draw(_ number: Int, fragmentTop: CGFloat) {
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = originY + fragmentTop + (lineHeight - size.height) / 2
            label.draw(at: CGPoint(x: width - size.width - 8, y: y), withAttributes: attributes)
        }
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, glyphRange, _ in
            let offset = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            if let number = self.lineNumber(startingAt: offset) { draw(number, fragmentTop: fragment.minY) }
        }
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty { draw(lineStarts.count, fragmentTop: extra.minY) }
    }
}

extension EditorFont {
    var editorLineHeight: CGFloat {
        #if canImport(UIKit)
        lineHeight
        #else
        ascender - descender + leading
        #endif
    }
}

#if canImport(UIKit)
extension UITextView {
    var string: String { text ?? "" }
}
#endif
