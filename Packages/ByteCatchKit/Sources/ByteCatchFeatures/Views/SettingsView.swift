import ByteCatchCore
import SwiftUI

public struct SettingsView: View {
    let session: SessionManager

    public init(session: SessionManager) {
        self.session = session
    }

    public var body: some View {
        Form {
            if case .signedIn(let server, let user) = session.state {
                Section("Account") {
                    LabeledContent("Server", value: server.base.absoluteString)
                    LabeledContent("Signed in as", value: user.username.isEmpty ? "—" : user.username)
                    Button("Sign Out", role: .destructive) {
                        SpotlightIndexer.removeAll()
                        session.signOut()
                    }
                    Button("Use a different server", role: .destructive) {
                        SpotlightIndexer.removeAll()
                        session.changeServer()
                    }
                }
            }
            Section("About") {
                LabeledContent(AboutText.appName, value: AboutText.version)
                Text(AboutText.tagline)
                Text(AboutText.privacy).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
