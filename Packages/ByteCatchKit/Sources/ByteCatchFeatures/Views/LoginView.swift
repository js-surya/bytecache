import ByteCatchCore
import SwiftUI

public struct LoginView: View {
    @Bindable var model: OnboardingModel
    let server: ServerURL

    public init(model: OnboardingModel, server: ServerURL) {
        self.model = model
        self.server = server
    }

    public var body: some View {
        Form {
            Section {
                TextField("Username", text: $model.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                    .onSubmit { Task { await model.login() } }
            } header: {
                Text("Sign in to \(server.base.host() ?? server.base.absoluteString)")
            } footer: {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await model.login() }
                } label: {
                    HStack {
                        Text("Sign In")
                        if model.isWorking { Spacer(); ProgressView() }
                    }
                }
                .disabled(!model.canLogin)
                .keyboardShortcut(.defaultAction)

                Button("Use a different server", role: .destructive) { model.changeServer() }
                    .disabled(model.isWorking)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}
