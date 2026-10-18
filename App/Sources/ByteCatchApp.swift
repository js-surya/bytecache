import SwiftUI
import ByteCatchFeatures

@main
struct ByteCatchApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView(services: services)
        }
        WindowGroup("Snippet", for: Int.self) { $id in
            if let id {
                SnippetWindow(id: id, services: services)
            }
        }
        #if os(macOS)
        Settings {
            SettingsView(session: services.session)
                .frame(width: 460, height: 360)
        }
        #endif
    }
}
