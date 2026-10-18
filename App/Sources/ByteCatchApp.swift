import SwiftUI
import ByteCatchFeatures

@main
struct ByteCatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        Settings {
            Text(AboutText.tagline)
                .padding()
        }
        #endif
    }
}
