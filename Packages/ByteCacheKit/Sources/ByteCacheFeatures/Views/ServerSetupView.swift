import ByteCacheCore
import SwiftUI

/// First screen: where is your ByteStash server?
public struct ServerSetupView: View {
    @Bindable var model: OnboardingModel
    @Environment(AppSettings.self) private var settings
    @Environment(CloudSyncCoordinator.self) private var cloudSync
    /// iCloud can take a few seconds to hand a new device its server list.
    @State private var checkingICloud = false

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        OnboardingForm {
            Section {
                VStack(spacing: 8) {
                    AppIconImage(size: 72)
                        .padding(.bottom, 4)
                    Text(AboutText.appName).font(.largeTitle.bold())
                    Text(AboutText.tagline).font(.title3.weight(.medium))
                    Text(AboutText.purpose).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            if !model.savedServers.isEmpty {
                Section {
                    savedServerList
                } header: {
                    HStack {
                        Text("Your Servers")
                        Spacer()
                        if settings.iCloudSyncEnabled {
                            Label("iCloud", symbol: .icloud)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    FooterText("Logins don't sync, so sign in once on each device.")
                }
            } else if checkingICloud {
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking iCloud for your servers…").foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Server address", text: $model.serverText, prompt: Text(verbatim: "https://bytestash.example.com"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { Task { await model.connect() } }
            } header: {
                Text(model.savedServers.isEmpty ? "Your ByteStash server" : "Or add another server")
            } footer: {
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                VStack(spacing: 14) {
                    Button {
                        Task { await model.connect() }
                    } label: {
                        ZStack {
                            Text("Connect").opacity(model.isWorking ? 0 : 1)
                            if model.isWorking { ProgressView() }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canConnect)
                    .keyboardShortcut(.defaultAction)

                    Button("Try the demo server") {
                        model.useDemoServer()
                        Task { await model.connect() }
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .disabled(model.isWorking)

                    Text("The demo server is public. Don't save real code there.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .task { await lookInICloud() }
        .toolbar {
            if model.session.canCancelAddServer {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Task { await model.cancelAddServer() } }
                }
            }
        }
        .logScreen("Server setup")
    }

    private var savedServerList: some View {
        ForEach(model.savedServers) { server in
            Button {
                Task { await model.useSavedServer(server.id) }
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon(server.apiKey != nil ? .key : .server, color: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.displayName).foregroundStyle(.primary)
                        if server.name != nil {
                            Text(server.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(server.isSignedIn ? "Open" : "Sign In").font(.subheadline).foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
                #if os(macOS)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                #endif
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)
        }
    }

    /// On a new device the list arrives from iCloud a moment after launch: ask now, and show that
    /// we're looking for a few seconds rather than an empty screen.
    private func lookInICloud() async {
        guard settings.iCloudSyncEnabled, model.savedServers.isEmpty else { return }
        checkingICloud = true
        await cloudSync.syncNow()
        try? await Task.sleep(for: .seconds(6))
        checkingICloud = false
    }
}
