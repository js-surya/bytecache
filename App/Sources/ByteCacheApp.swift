import SwiftUI
import ByteCacheFeatures

@main
struct ByteCacheApp: App {
    @State private var services = AppServices()

    init() {
        CopyToastWindow.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView(services: services)
                .appSettingsStyle(services.settings)
                .environment(services.cloudSync)
                .environment(services.lock)
                .environment(services.updates)
                .appLockCover(services.lock)
        }
        .commands {
            SnippetCommandsMenu()
            #if os(macOS)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await services.updates.checkNow() } }
            }
            #endif
        }
        WindowGroup("Snippet", for: Int.self) { $id in
            if let id {
                SnippetWindow(id: id, services: services)
                    .appSettingsStyle(services.settings)
                .environment(services.cloudSync)
                .environment(services.lock)
                .appLockCover(services.lock)
            }
        }
        #if os(macOS)
        Settings {
            MacSettingsView(session: services.session)
            .appSettingsStyle(services.settings)
                .environment(services.cloudSync)
                .environment(services.lock)
                .environment(services.updates)
                .appLockCover(services.lock)
            .frame(minWidth: 720, idealWidth: 780, minHeight: 520, idealHeight: 600)
        }
        #endif
    }
}
