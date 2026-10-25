import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Select mode on the Mac (CP-86). A Mac list replaces its selection on a plain click (adding takes ⌘
/// or ⇧), so in Select mode only one snippet could be picked. Here a plain click adds or removes
/// that snippet, as on iPhone and iPad; ⌘- and ⇧-clicks and the arrow keys keep their usual meaning.
enum SelectModeSelection {
    /// The selection after the list proposes `new`. `plainClick`: a mouse click without ⌘ or ⇧.
    static func apply(old: Set<Int>, new: Set<Int>, plainClick: Bool) -> Set<Int> {
        guard plainClick, new.count == 1, let id = new.first else { return new }
        var result = old
        if result.contains(id) { result.remove(id) } else { result.insert(id) }
        return result
    }

    /// Whether the event being handled is a mouse click without ⌘ or ⇧.
    @MainActor
    static var isPlainClick: Bool {
        #if os(macOS)
        guard let event = NSApp.currentEvent,
              [.leftMouseDown, .leftMouseUp].contains(event.type) else { return false }
        return event.modifierFlags.intersection([.command, .shift]).isEmpty
        #else
        return false
        #endif
    }
}
