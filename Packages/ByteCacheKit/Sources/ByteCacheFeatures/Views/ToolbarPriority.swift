import SwiftUI

/// How readily a toolbar item moves to the overflow menu when the bar is short of room, such as the
/// vertical bars on iPhone Duo (CP-83). No effect before iOS 27 / macOS 26.1.
public enum ToolbarPriority {
    case low, high
}

extension ToolbarContent {
    @ToolbarContentBuilder
    public func overflowPriority(_ priority: ToolbarPriority) -> some ToolbarContent {
        if #available(iOS 27, macOS 26.1, *) {
            visibilityPriority(priority == .high ? .high : .low)
        } else {
            self
        }
    }
}

extension CustomizableToolbarContent {
    @ToolbarContentBuilder
    public func overflowPriority(_ priority: ToolbarPriority) -> some CustomizableToolbarContent {
        if #available(iOS 27, macOS 26.1, *) {
            visibilityPriority(priority == .high ? .high : .low)
        } else {
            self
        }
    }
}
