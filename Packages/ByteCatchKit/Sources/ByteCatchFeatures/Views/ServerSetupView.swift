import SwiftUI

/// First screen: where is your ByteStash server?
public struct ServerSetupView: View {
    @Bindable var model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Icon(.appMark, size: 48)
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text(AboutText.appName).font(.largeTitle.bold())
                    Text(AboutText.tagline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                TextField("Server address", text: $model.serverText, prompt: Text("https://bytestash.example.com"))
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
                Button {
                    Task { await model.connect() }
                } label: {
                    HStack {
                        Text("Connect")
                        if model.isWorking { Spacer(); ProgressView() }
                    }
                }
                .disabled(!model.canConnect)
                .keyboardShortcut(.defaultAction)

                Button("Try the demo server") {
                    model.useDemoServer()
                    Task { await model.connect() }
                }
                .disabled(model.isWorking)
            } footer: {
                Text("The demo server is public. Don't save real code there.")
            }
        }
        .formStyle(.grouped)
        .toolbar {
            if model.session.canCancelAddServer {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Task { await model.cancelAddServer() } }
                }
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}
