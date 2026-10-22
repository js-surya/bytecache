#if canImport(UIKit)
import SwiftUI
import UIKit

struct PlatformCodeEditor: UIViewRepresentable {
    @Binding var text: String
    let style: EditorStyle

    func makeCoordinator() -> CodeEditorCoordinator {
        CodeEditorCoordinator(text: $text, style: style)
    }

    func makeUIView(context: Context) -> CodeUITextView {
        let coordinator = context.coordinator
        // TextKit 1: the line-number gutter reads line fragments from the layout manager.
        // Built by hand: `init(usingTextLayoutManager:)` skips this subclass's initializer.
        let (storage, container) = TextKit1.stack()
        coordinator.ownedStorage = storage
        let view = CodeUITextView(frame: .zero, textContainer: container)
        view.coordinator = coordinator
        view.delegate = view
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.inlinePredictionType = .no
        view.isFindInteractionEnabled = true
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        view.inputAccessoryView = EditorKeyBar.make(for: view, iconStyle: context.environment.iconStyle)
        coordinator.textView = view
        coordinator.redrawGutter = { [weak view] in view?.layoutGutter() }
        coordinator.restyle(style)
        coordinator.load(text)
        return view
    }

    func updateUIView(_ view: CodeUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        if coordinator.style != style { coordinator.restyle(style) }
        if view.string != text { coordinator.load(text) }
    }
}

final class CodeUITextView: UITextView, UITextViewDelegate {
    weak var coordinator: CodeEditorCoordinator?
    private let gutter = LineNumberGutter()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        gutter.isUserInteractionEnabled = false
        gutter.backgroundColor = .clear
        gutter.contentMode = .redraw
        addSubview(gutter)
    }

    required init?(coder: NSCoder) { fatalError("not used from storyboards") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutGutter()
    }

    func layoutGutter() {
        guard let coordinator else { return }
        let width = coordinator.gutterWidth
        gutter.isHidden = width == 0
        if textContainerInset.left != width + 8 { textContainerInset.left = width + 8 }
        gutter.frame = CGRect(x: 0, y: contentOffset.y, width: width, height: bounds.height)
        gutter.owner = self
        gutter.setNeedsDisplay()
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        coordinator?.shouldChange(range: range, replacement: text) ?? true
    }

    func textViewDidChange(_ textView: UITextView) {
        coordinator?.textChanged()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        coordinator?.selectionChanged()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layoutGutter()
    }
}

enum TextKit1 {
    /// The storage owns the layout manager, but nothing owns the storage: the caller must keep it.
    static func stack() -> (NSTextStorage, NSTextContainer) {
        let storage = NSTextStorage(), layoutManager = NSLayoutManager(), container = NSTextContainer()
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        return (storage, container)
    }
}

/// Line numbers, drawn for the visible part of the text view only.
final class LineNumberGutter: UIView {
    weak var owner: CodeUITextView?

    override func draw(_ rect: CGRect) {
        guard let owner, let coordinator = owner.coordinator else { return }
        let inset = owner.textContainerInset
        // Visible area in text-container coordinates.
        let visible = CGRect(x: 0, y: owner.contentOffset.y - inset.top, width: owner.bounds.width, height: owner.bounds.height)
        coordinator.drawLineNumbers(in: rect, visible: visible, originY: inset.top - owner.contentOffset.y, width: bounds.width)
    }
}

/// Keys that are awkward on a phone keyboard, plus Find & Replace.
@MainActor
enum EditorKeyBar {
    static func make(for view: CodeUITextView, iconStyle: IconStyle) -> UIView {
        let keys = ["⇥", "{", "}", "(", ")", "[", "]", "\"", "'", "=", ";", ":", "<", ">", "/", "|", "$", "_"]
        var buttons: [UIButton] = keys.map { key in
            var config = UIButton.Configuration.gray()
            config.title = key
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            config.attributedTitle = AttributedString(key, attributes: AttributeContainer([.font: UIFont.monospacedSystemFont(ofSize: 16, weight: .medium)]))
            let button = UIButton(configuration: config, primaryAction: UIAction { [weak view] _ in
                view?.coordinator?.type(key == "⇥" ? "\t" : key)
            })
            if key == "⇥" { button.accessibilityLabel = "Tab" }
            return button
        }
        var find = UIButton.Configuration.gray()
        find.image = AppSymbol.search.uiImage(iconStyle)
        buttons.insert(UIButton(configuration: find, primaryAction: UIAction { [weak view] _ in
            view?.findInteraction?.presentFindNavigator(showingReplace: true)
        }), at: 0)
        buttons[0].accessibilityLabel = "Find and Replace"
        var done = UIButton.Configuration.gray()
        done.image = AppSymbol.hideKeyboard.uiImage(iconStyle)
        let doneButton = UIButton(configuration: done, primaryAction: UIAction { [weak view] _ in _ = view?.resignFirstResponder() })
        doneButton.accessibilityLabel = "Hide Keyboard"

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 48), inputViewStyle: .keyboard)
        bar.allowsSelfSizing = true
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(scroll)
        bar.addSubview(doneButton)
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 48),
            scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: bar.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            doneButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            doneButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 36),
        ])
        return bar
    }
}

extension AppSymbol {
    /// The icon for UIKit controls, in the chosen style.
    func uiImage(_ style: IconStyle) -> UIImage? {
        switch style {
        case .sfSymbols: UIImage(systemName: sfName)
        case .lucide: UIImage(named: lucideAsset, in: .module, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
        }
    }
}
#endif
