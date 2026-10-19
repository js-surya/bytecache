import SwiftUI
import ByteCatchFeatures

@main
struct ByteCatchApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView(services: services)
                .appSettingsStyle(services.settings)
                .environment(services.cloudSync)
        }
        .commands { SnippetCommandsMenu() }
        WindowGroup("Snippet", for: Int.self) { $id in
            if let id {
                SnippetWindow(id: id, services: services)
                    .appSettingsStyle(services.settings)
                .environment(services.cloudSync)
            }
        }
        #if os(macOS)
        Settings {
            NavigationStack {
                SettingsView(session: services.session)
            }
            .appSettingsStyle(services.settings)
                .environment(services.cloudSync)
            .frame(width: 520, height: 560)
        }
        #endif
    }
}
