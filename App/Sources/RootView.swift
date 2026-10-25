import SwiftUI
import ByteCacheCore
import ByteCacheFeatures

/// Routes between server setup, login and the main split view.
struct RootView: View {
    /// Snippet from another device: switch to its server (or offer to add it), then show it.
    private func openHandoff(server: ServerURL, snippetID: Int) async {
        let session = services.session
        if let account = session.accounts.first(where: { $0.server == server }) {
            if account.id != session.activeAccountID { await session.switchTo(account.id) }
            AppNavigator.shared.pendingSnippetID = snippetID
        } else {
            session.addServer()
            services.onboarding.serverText = server.base.absoluteString
        }
    }

    let services: AppServices
    @State private var restored = false
    /// After a crash: offer a report once per launch.

    /// Debug: `-BCLoadingPreview` shows only the loading animation (screenshots).
    private static var previewLoading: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-BCLoadingPreview")
        #else
        false
        #endif
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if Self.previewLoading {
                LoadingMark("Loading snippets…")
            } else if !restored {
                LoadingMark()
            } else {
                switch services.session.state {
                case .needsServer:
                    NavigationStack { ServerSetupView(model: services.onboarding) }
                        .onboardingWindowSize()
                case .needsLogin(let server, _):
                    NavigationStack { LoginView(model: services.onboarding, server: server) }
                        .onboardingWindowSize()
                case .signedIn:
                    // A fresh list, sidebar and selection for each server.
                    MainSplitView(services: services)
                        .id(services.session.activeAccountID)
                }
            }
        }
        .animation(.default, value: services.session.state)
        // A key that keeps this device signed in once the server ends the login (CP-91).
        .task(id: services.session.state) {
            guard case .signedIn = services.session.state else { return }
            await services.session.ensureBackupKey(name: SessionManager.backupKeyName())
        }
        .onOpenURL { url in
            if let link = DeepLink(url: url) { AppNavigator.shared.handle(link) }
        }
        .onChange(of: scenePhase) { _, phase in
            CrashReporting.scenePhaseChanged(phase)
            if phase == .active, let link = PendingCapture.consume() { AppNavigator.shared.handle(link) }
            if phase == .active {
                Task { await services.updates.appBecameActive() }
                Task { await services.serverSettings.pull() }
            }
        }
        .sheet(item: Bindable(services.updates).whatsNew) { release in
            WhatsNewSheet(release: release).appSettingsStyle(services.settings)
        }
        .onChange(of: services.session.state) {
            // Signing in refreshes too, so a first load that fails shows up in the widget.
            Task { await services.widgets.refresh() }
            if case .signedIn = services.session.state { Task { await services.serverSettings.pull() } }
        }
        .onContinueUserActivity(SnippetActivity.type) { activity in
            guard services.settings.handoffEnabled, let target = SnippetActivity.parse(activity.userInfo) else { return }
            Task { await openHandoff(server: target.server, snippetID: target.snippetID) }
        }
        .task {
            guard !restored else { return }
            Task { await services.updates.appBecameActive() }
            await services.session.restore()
            // After a crash, a toast instead of a prompt, once the app is on screen; the report waits
            // in Settings → Report a Bug.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                CrashReporting.announceUnexpectedEnd()
            }
            #if DEBUG
            // `-BCDemoLogin` launch argument: sign in to the public demo (screenshots, quick checks).
            if ProcessInfo.processInfo.arguments.contains("-BCDemoLogin"), case .needsServer = services.session.state {
                services.onboarding.useDemoServer()
                await services.onboarding.connect()
                await services.onboarding.login()
            }
            // `-BCKeyLogin` with env BC_DEBUG_SERVER and BC_DEBUG_API_KEY: sign in to that server with an API key.
            let env = ProcessInfo.processInfo.environment
            if ProcessInfo.processInfo.arguments.contains("-BCKeyLogin"), services.session.client == nil,
               let server = env["BC_DEBUG_SERVER"], let key = env["BC_DEBUG_API_KEY"] {
                // Also from another server's sign-in screen (a simulator that remembers the demo).
                if case .needsLogin = services.session.state { services.session.changeServer() }
                try? await services.session.connect(server)
                try? await services.session.loginWithAPIKey(key)
            }
            // `-BCPasswordLogin` with env BC_DEBUG_SERVER, BC_DEBUG_USER and BC_DEBUG_PASSWORD: sign in with a
            // password (tests the backup key that keeps the app signed in, CP-91).
            if ProcessInfo.processInfo.arguments.contains("-BCPasswordLogin"), services.session.client == nil,
               let server = env["BC_DEBUG_SERVER"], let user = env["BC_DEBUG_USER"], let password = env["BC_DEBUG_PASSWORD"] {
                if case .needsLogin = services.session.state { services.session.changeServer() }
                try? await services.session.connect(server)
                try? await services.session.login(username: user, password: password)
            }
            // `-BCCopyToast`: show the "Copied" toast every 3 s (screenshots).
            if ProcessInfo.processInfo.arguments.contains("-BCCopyToast") {
                Task {
                    while true {
                        try? await Task.sleep(for: .seconds(3))
                        CopyFeedback.copied()
                    }
                }
            }
            // `-BCExpireSession`: the server stops accepting the login, as when a session expires.
            if ProcessInfo.processInfo.arguments.contains("-BCExpireSession") { services.session.debugExpireSession() }
            // `-BCExpiryDemo`: snippets 9 and 10 expire in 50 minutes and 2 days (screenshots).
            if ProcessInfo.processInfo.arguments.contains("-BCExpiryDemo"), let server = services.session.client?.server {
                services.settings.setExpiry(Date().addingTimeInterval(50 * 60), snippetID: 9, server: server)
                services.settings.setExpiry(Date().addingTimeInterval(2 * 86_400 + 4 * 3600), snippetID: 10, server: server)
            }
            // `-BCOpenSnippet <id>`: open a snippet once signed in (screenshots).
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-BCOpenSnippet"),
               ProcessInfo.processInfo.arguments.indices.contains(i + 1),
               let id = Int(ProcessInfo.processInfo.arguments[i + 1]) {
                AppNavigator.shared.pendingSnippetID = id
            }
            // `BC_DEBUG_API_KEY` environment variable: pre-fill the API key field (simulator clipboard sync is unreliable).
            if let key = ProcessInfo.processInfo.environment["BC_DEBUG_API_KEY"], case .needsLogin = services.session.state {
                services.onboarding.method = .apiKey
                services.onboarding.apiKey = key
            }
            #endif
            restored = true
            if let link = PendingCapture.consume() { AppNavigator.shared.handle(link) }
            await services.cloudSync.start()
            services.aiNotes.start()
        }
    }
}

private extension View {
    /// Room for the whole server or sign-in screen without scrolling on the Mac.
    func onboardingWindowSize() -> some View {
        #if os(macOS)
        frame(minWidth: 480, minHeight: 700)
        #else
        self
        #endif
    }
}
