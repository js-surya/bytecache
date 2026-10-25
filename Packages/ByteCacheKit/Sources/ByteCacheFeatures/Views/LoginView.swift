import ByteCacheCore
import SwiftUI

public struct LoginView: View {
    @Bindable var model: OnboardingModel
    let server: ServerURL
    @State private var showKey = false
    @State private var signingInWithSSO = false

    public init(model: OnboardingModel, server: ServerURL) {
        self.model = model
        self.server = server
    }

    private var host: String { server.base.host() ?? server.base.absoluteString }

    public var body: some View {
        OnboardingForm {
            Section {
                VStack(spacing: 8) {
                    Icon(model.method == .apiKey ? .key : .person)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentTransition(.symbolEffect(.replace))
                    Text(model.creatingAccount ? "Create Account" : "Sign In").font(.title.bold())
                    Label(host, symbol: .server)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            if !model.creatingAccount && !model.passwordsDisabled {
                Section {
                    Picker("Sign in with", selection: $model.method.animation()) {
                        ForEach(OnboardingModel.LoginMethod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    #if os(macOS)
                    // A Mac segmented control keeps its natural width; centre it under the heading.
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                    #endif
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

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
                        .textContentType(model.creatingAccount ? .newPassword : .password)
                        .onSubmit(signIn)
                    if model.creatingAccount {
                        SecureField("Confirm Password", text: $model.confirmPassword)
                            .textContentType(.newPassword)
                            .onSubmit(signIn)
                    }
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
                Group {
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(.red)
                    } else if model.passwordsDiffer {
                        Text("The passwords don't match.").foregroundStyle(.red)
                    } else if model.creatingAccount {
                        FooterText("Creates an account on this server and signs you in.")
                    } else if model.session.sessionExpired {
                        Text("Your sign-in expired: ByteStash ends sign-ins after a while (24 hours unless the server is set otherwise). Sign in again, and ByteCache will keep you signed in from then on.")
                            .foregroundStyle(.orange)
                    } else if model.method == .apiKey {
                        FooterText("Create a key in ByteStash under Settings → API Keys. It's kept in the Keychain on this device.")
                    }
                }
                .font(.footnote)
            }

            Section {
                VStack(spacing: 14) {
                    Button(action: signIn) {
                        ZStack {
                            Text(model.creatingAccount ? "Create Account" : "Sign In").opacity(model.isWorking ? 0 : 1)
                            if model.isWorking { ProgressView() }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canLogin)
                    .keyboardShortcut(.defaultAction)

                    if let title = model.ssoTitle, !model.creatingAccount {
                        Button { signingInWithSSO = true } label: {
                            Label(title, symbol: .key).font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(model.isWorking)
                    }

                    if model.canCreateAccount && !model.passwordsDisabled && (model.method == .password || model.creatingAccount) {
                        Button(model.creatingAccount ? "I Already Have an Account" : "Create Account") {
                            withAnimation { model.toggleCreatingAccount() }
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                        .disabled(model.isWorking)
                    }

                    Button("Use a Different Server") { model.changeServer() }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                        .disabled(model.isWorking)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .task {
            await model.session.loadSSO()
            if model.passwordsDisabled { model.method = .apiKey }
        }
        .sheet(isPresented: $signingInWithSSO) {
            SingleSignOnSheet(server: server, title: model.ssoTitle ?? "Single Sign-On") { token in
                Task { await model.signIn(ssoToken: token) }
            }
        }
        .logScreen("Sign in")
    }

    private func signIn() {
        guard model.canLogin else { return }
        Task { await model.login() }
    }
}
