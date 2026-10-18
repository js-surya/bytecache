import SwiftUI

/// Temporary share-extension UI; replaced by `CaptureSheet` in plan Task 12/13.
public struct SharePlaceholderView: View {
    private let onDone: () -> Void

    public init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text(AboutText.appName).font(.headline)
            Text("Capture coming soon").foregroundStyle(.secondary)
            Button("Done", action: onDone).keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 200)
    }
}
