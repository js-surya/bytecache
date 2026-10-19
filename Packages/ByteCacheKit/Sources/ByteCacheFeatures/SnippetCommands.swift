import SwiftUI

/// Actions the menu bar / hardware-keyboard commands run against the focused window.
public struct SnippetCommandActions {
    public var newSnippet: () -> Void
    public var refresh: () -> Void
    public var focusSearch: () -> Void
    public var edit: (() -> Void)?
    public var copyCode: (() -> Void)?
    public var recycle: (() -> Void)?

    public init(newSnippet: @escaping () -> Void, refresh: @escaping () -> Void, focusSearch: @escaping () -> Void,
                edit: (() -> Void)?, copyCode: (() -> Void)?, recycle: (() -> Void)?) {
        self.newSnippet = newSnippet
        self.refresh = refresh
        self.focusSearch = focusSearch
        self.edit = edit
        self.copyCode = copyCode
        self.recycle = recycle
    }
}

extension FocusedValues {
    @Entry public var snippetCommands: SnippetCommandActions?
}

public struct SnippetCommandsMenu: Commands {
    @FocusedValue(\.snippetCommands) private var actions

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Snippet") { actions?.newSnippet() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandMenu("Snippet") {
            Button("Find") { actions?.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions == nil)
            Button("Refresh") { actions?.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions == nil)
            Divider()
            Button("Edit") { actions?.edit?() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(actions?.edit == nil)
            Button("Copy Code") { actions?.copyCode?() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(actions?.copyCode == nil)
            Divider()
            Button("Move to Recycle Bin") { actions?.recycle?() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(actions?.recycle == nil)
        }
    }
}
