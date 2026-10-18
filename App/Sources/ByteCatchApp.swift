import SwiftUI
import ByteCatchFeatures

@main
struct ByteCatchApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView(services: services)
        }
        #if os(macOS)
        Settings {
            SettingsView(session: services.session)
                .frame(width: 460, height: 360)
        }
        #endif
    }
}
