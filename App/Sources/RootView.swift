import SwiftUI
import ByteCatchCore
import ByteCatchFeatures

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

    var body: some View {
        Group {
            if !restored {
                ProgressView()
            } else {
                switch services.session.state {
                case .needsServer:
                    NavigationStack { ServerSetupView(model: services.onboarding) }
                case .needsLogin(let server, _):
                    NavigationStack { LoginView(model: services.onboarding, server: server) }
                case .signedIn:
                    // A fresh list, sidebar and selection for each server.
                    MainSplitView(services: services)
                        .id(services.session.activeAccountID)
                }
            }
        }
        .animation(.default, value: services.session.state)
        .onContinueUserActivity(SnippetActivity.type) { activity in
            guard services.settings.handoffEnabled, let target = SnippetActivity.parse(activity.userInfo) else { return }
            Task { await openHandoff(server: target.server, snippetID: target.snippetID) }
        }
        .task {
            guard !restored else { return }
            await services.session.restore()
            #if DEBUG
            // `-BCDemoLogin` launch argument: sign in to the public demo (screenshots, quick checks).
            if ProcessInfo.processInfo.arguments.contains("-BCDemoLogin"), case .needsServer = services.session.state {
                services.onboarding.useDemoServer()
                await services.onboarding.connect()
                await services.onboarding.login()
            }
            // `BC_DEBUG_API_KEY` environment variable: pre-fill the API key field (simulator clipboard sync is unreliable).
            if let key = ProcessInfo.processInfo.environment["BC_DEBUG_API_KEY"], case .needsLogin = services.session.state {
                services.onboarding.method = .apiKey
                services.onboarding.apiKey = key
            }
            #endif
            restored = true
            await services.cloudSync.start()
        }
    }
}
