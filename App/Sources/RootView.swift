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
    @State private var offerCrashReport = CrashWatch.shared.endedUnexpectedly
    @State private var reportingCrash = false

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
        .onOpenURL { url in
            if let link = DeepLink(url: url) { AppNavigator.shared.handle(link) }
        }
        .onChange(of: scenePhase) { _, phase in
            CrashReporting.scenePhaseChanged(phase)
            if phase == .active, let link = PendingCapture.consume() { AppNavigator.shared.handle(link) }
            if phase == .active { Task { await services.updates.appBecameActive() } }
        }
        .alert("ByteCache Closed Unexpectedly", isPresented: $offerCrashReport) {
            Button("Report…") { reportingCrash = true }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Send a short report so it can be fixed? You'll see everything in it before it's sent.")
        }
        .sheet(isPresented: $reportingCrash) {
            NavigationStack {
                ReportBugView(model: ReportBugModel(session: services.session, title: "ByteCache closed unexpectedly"),
                              showsCancel: true)
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 600)
            #endif
        }
        .sheet(item: Bindable(services.updates).offered) { release in
            UpdateSheet(release: release, kind: .update, current: services.updates.runningVersion) {
                services.updates.skipOffered()
            }
            .appSettingsStyle(services.settings)
        }
        .background {
            // A second sheet needs its own anchor view.
            Color.clear.sheet(item: Bindable(services.updates).whatsNew) { release in
                UpdateSheet(release: release, kind: .whatsNew).appSettingsStyle(services.settings)
            }
        }
        .onChange(of: services.session.state) {
            // Signing in refreshes too, so a first load that fails shows up in the widget.
            Task { await services.widgets.refresh() }
        }
        .onContinueUserActivity(SnippetActivity.type) { activity in
            guard services.settings.handoffEnabled, let target = SnippetActivity.parse(activity.userInfo) else { return }
            Task { await openHandoff(server: target.server, snippetID: target.snippetID) }
        }
        .task {
            guard !restored else { return }
            Task { await services.updates.appBecameActive() }
            await services.session.restore()
            #if DEBUG
            // `-BCDemoLogin` launch argument: sign in to the public demo (screenshots, quick checks).
            if ProcessInfo.processInfo.arguments.contains("-BCDemoLogin"), case .needsServer = services.session.state {
                services.onboarding.useDemoServer()
                await services.onboarding.connect()
                await services.onboarding.login()
            }
            // `-BCKeyLogin` with env BC_DEBUG_SERVER and BC_DEBUG_API_KEY: sign in to that server with an API key.
            let env = ProcessInfo.processInfo.environment
            if ProcessInfo.processInfo.arguments.contains("-BCKeyLogin"), case .needsServer = services.session.state,
               let server = env["BC_DEBUG_SERVER"], let key = env["BC_DEBUG_API_KEY"] {
                try? await services.session.connect(server)
                try? await services.session.loginWithAPIKey(key)
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
