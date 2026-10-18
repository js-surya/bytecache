import SwiftUI
import ByteCatchFeatures

/// Routes between server setup, login and the main split view.
struct RootView: View {
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
            #endif
            restored = true
        }
    }
}
