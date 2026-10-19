import SwiftUI

#if os(iOS)
/// The Settings button: top left in every iPhone and iPad view, with the same icon and label.
/// Defined once so its place can't drift between views. (On Mac, Settings is the app's Settings window.)
public struct SettingsToolbarItem: ToolbarContent {
    public static let placement = ToolbarItemPlacement.topBarLeading
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: Self.placement) {
            Button(action: action) { Label("Settings", symbol: .settings) }
                .accessibilityLabel("Settings")
        }
    }
}
#endif
