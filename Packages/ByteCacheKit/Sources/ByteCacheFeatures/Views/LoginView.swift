import ByteCacheCore
import SwiftUI

public struct LoginView: View {
    @Bindable var model: OnboardingModel
    let server: ServerURL
    @State private var showKey = false

    public init(model: OnboardingModel, server: ServerURL) {
        self.model = model
        self.server = server
    }

    private var host: String { server.base.host() ?? server.base.absoluteString }

    public var body: some View {
        OnboardingForm {
            Section {
                VStack(spacing: 8) {
                    Icon(model.method == .apiKey ? .key : .person, size: 28)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentTransition(.symbolEffect(.replace))
                    Text("Sign In").font(.title.bold())
                    Label(host, symbol: .server)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            Section {
                Picker("Sign in with", selection: $model.method.animation()) {
                    ForEach(OnboardingModel.LoginMethod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                switch model.method {
                case .password:
                    TextField("Username", text: $model.username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("Password", text: $model.password)
                        .textContentType(.password)
                        .onSubmit(signIn)
                case .apiKey:
                    HStack(spacing: 14) {
                        Group {
                            if showKey {
                                TextField("API key", text: $model.apiKey)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("API key", text: $model.apiKey)
                            }
                        }
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(signIn)

                        Button {
                            if let text = Pasteboard.string() {
                                model.apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Icon(.clipboard)
                        }
                        .accessibilityLabel("Paste API key")

                        Button { showKey.toggle() } label: {
                            Icon(showKey ? .eyeOff : .eye)
                        }
                        .accessibilityLabel(showKey ? "Hide API key" : "Show API key")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                } else if model.session.sessionExpired {
                    Text("Your session expired. Sign in again to continue.").foregroundStyle(.orange)
                } else if model.method == .apiKey {
                    Text("Create a key in ByteStash under Settings → API Keys. It's kept in the Keychain on this device.")
                }
            }

            Section {
                VStack(spacing: 14) {
                    Button(action: signIn) {
                        ZStack {
                            Text("Sign In").opacity(model.isWorking ? 0 : 1)
                            if model.isWorking { ProgressView() }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canLogin)
                    .keyboardShortcut(.defaultAction)

                    Button("Use a Different Server") { model.changeServer() }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                        .disabled(model.isWorking)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func signIn() {
        guard model.canLogin else { return }
        Task { await model.login() }
    }
}
