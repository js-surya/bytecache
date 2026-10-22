import SwiftUI
import ByteCacheFeatures

@main
struct ByteCacheApp: App {
    @State private var services = AppServices()

    init() {
        CopyToastWindow.install()
        CrashReporting.appLaunched()
    }

    var body: some Scene {
        WindowGroup {
            RootView(services: services)
                .appSettingsStyle(services.settings)
                .environment(services.cloudSync)
                .environment(services.lock)
                .environment(services.updates)
                .appLockCover(services.lock)
                #if os(macOS)
                .task {
                    QuickSearchPanel.shared.configure(services)
                    SystemAppIconSwitcher.shared.apply()
                    ActiveAppPaster.shared.start()
                    applyDockPolicy(menuBarOnly: services.settings.menuBarOnly)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-BCAccessibilityGuide") { AccessibilityGuide.shared.show() }
                    #endif
                }
                .onChange(of: services.settings.menuBarOnly) { _, only in
                    applyDockPolicy(menuBarOnly: only)
                }
                .onChange(of: services.settings.quickSearchShortcut) { _, shortcut in
                    GlobalHotKey.shared.register(shortcut)
                }
                #endif
        }
        .commands {
            SnippetCommandsMenu()
            #if os(macOS)
            // View → Show/Hide Toolbar and Customize Toolbar… (CP-71).
            ToolbarCommands()
            CommandGroup(replacing: .help) {
                ReportBugMenuItem()
            }
            CommandGroup(after: .appInfo) {
                if services.updates.offersUpdates {
                    Button("Check for Updates…") { Task { await services.updates.checkNow() } }
                }
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
        Window("Report a Bug", id: "report-bug") {
            NavigationStack {
                ReportBugView(model: ReportBugModel(session: services.session), showsCancel: true)
            }
            .appSettingsStyle(services.settings)
            .frame(minWidth: 520, idealWidth: 560, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        Settings {
            MacSettingsView(session: services.session)
            .appSettingsStyle(services.settings)
                .environment(services.cloudSync)
                .environment(services.lock)
                .environment(services.updates)
                .appLockCover(services.lock)
            .frame(minWidth: 720, idealWidth: 780, minHeight: 520, idealHeight: 600)
        }
        MenuBarExtra(isInserted: Bindable(services.settings).quickSearchInMenuBar) {
            MenuBarQuickSearch(services: services)
        } label: {
            Label("ByteCache Quick Search", systemImage: "curlybraces")
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if os(macOS)
/// Help → Report a Bug…
private struct ReportBugMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Report a Bug…") { openWindow(id: "report-bug") }
    }

}
#endif

#if os(macOS)
/// Menu Bar Only (CP-69): no Dock icon or app switcher entry; the menu bar icon stays.
@MainActor private func applyDockPolicy(menuBarOnly: Bool) {
    let policy: NSApplication.ActivationPolicy = menuBarOnly ? .accessory : .regular
    guard NSApp.activationPolicy() != policy else { return }
    NSApp.setActivationPolicy(policy)
    // Changing the policy sends ByteCache to the back; keep the window you changed it from in front.
    NSApp.activate()
}
#endif
