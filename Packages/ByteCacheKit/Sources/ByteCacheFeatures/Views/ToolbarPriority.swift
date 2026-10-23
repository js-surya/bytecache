import SwiftUI

/// How readily toolbar items move to the overflow menu when the bar is short of room, such as the
/// vertical bars on iPhone Duo (CP-83). No effect before iOS 27 / macOS 26.1.
public enum ToolbarPriority {
    case low, high

    @available(iOS 27, macOS 26.1, *)
    var visibility: ToolbarItemVisibilityPriority { self == .high ? .high : .low }
}

// The availability check sits in a view builder, not a toolbar builder: `if #available` inside a
// toolbar builder links on the simulator but not on devices with the iOS 27.1 SDK
// (ToolbarContentBuilder.buildLimitedAvailability is missing there).
extension View {
    /// `.toolbar { … }` whose items get this overflow priority.
    @ViewBuilder
    public func toolbar<Content: ToolbarContent>(
        overflowPriority priority: ToolbarPriority, @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 27, macOS 26.1, *) {
            toolbar { content().visibilityPriority(priority.visibility) }
        } else {
            toolbar(content: content)
        }
    }

    /// `.toolbar(id:) { … }` whose items get this overflow priority. Toolbars with the same id merge,
    /// so this adds to the window's customisable toolbar.
    @ViewBuilder
    public func toolbar<Content: CustomizableToolbarContent>(
        id: String, overflowPriority priority: ToolbarPriority, @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 27, macOS 26.1, *) {
            toolbar(id: id) { content().visibilityPriority(priority.visibility) }
        } else {
            toolbar(id: id, content: content)
        }
    }
}
