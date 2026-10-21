import SwiftUI

/// First screen: where is your ByteStash server?
public struct ServerSetupView: View {
    @Bindable var model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        OnboardingForm {
            Section {
                VStack(spacing: 8) {
                    Icon(.appMark, size: 48)
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text(AboutText.appName).font(.largeTitle.bold())
                    Text(AboutText.tagline).font(.title3.weight(.medium))
                    Text(AboutText.purpose).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                TextField("Server address", text: $model.serverText, prompt: Text(verbatim: "https://bytestash.example.com"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { Task { await model.connect() } }
            } header: {
                Text("Your ByteStash server")
            } footer: {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
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
        .toolbar {
            if model.session.canCancelAddServer {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Task { await model.cancelAddServer() } }
                }
            }
        }
    }
}
