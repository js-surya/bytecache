import SwiftUI
import ByteCatchFeatures

/// Routes between server setup, login and the main split view (plan Task 9).
struct RootView: View {
    var body: some View {
        ContentUnavailableView {
            Label(AboutText.appName, systemImage: "curlybraces")
        } description: {
            Text(AboutText.tagline)
        }
    }
}

#Preview {
    RootView()
}
