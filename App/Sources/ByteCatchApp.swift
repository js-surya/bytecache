import SwiftUI
import ByteCatchFeatures

@main
struct ByteCatchApp: App {
    @State private var services = AppServices()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView(services: services)
                .appSettingsStyle(settings)
        }
        .commands { SnippetCommandsMenu() }
        WindowGroup("Snippet", for: Int.self) { $id in
            if let id {
                SnippetWindow(id: id, services: services)
                    .appSettingsStyle(settings)
            }
        }
        #if os(macOS)
        Settings {
            NavigationStack {
                SettingsView(session: services.session)
            }
            .appSettingsStyle(settings)
            .frame(width: 520, height: 560)
        }
        #endif
    }
}
