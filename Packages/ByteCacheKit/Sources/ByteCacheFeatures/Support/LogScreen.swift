import ByteCacheCore
import SwiftUI

extension View {
    /// Notes in the activity log that this screen appeared: its name only, for bug reports.
    func logScreen(_ name: String) -> some View {
        onAppear { AppLog.shared.record("screen", name) }
    }
}

extension FragmentDraft {
    static func logSummary(_ fragments: [FragmentDraft]) -> String {
        "\(fragments.count) file\(fragments.count == 1 ? "" : "s"), \(AppLog.size(fragments.reduce(0) { $0 + $1.code.utf8.count }))"
    }
}
