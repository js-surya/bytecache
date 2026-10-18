import SwiftUI
import ByteCatchFeatures

/// Sidebar | list | detail (plan Task 10).
struct MainSplitView: View {
    let services: AppServices

    var body: some View {
        NavigationStack {
            SettingsView(session: services.session)
        }
    }
}
