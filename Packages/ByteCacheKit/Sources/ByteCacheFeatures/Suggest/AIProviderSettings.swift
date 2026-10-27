import SwiftUI
import ByteCacheCore

/// The person's own provider: key, server address and model, with a connection check (CP-93).
struct AIProviderSection: View {
    let provider: AIProvider
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var keyDraft = ""
    @State private var models: [String] = []
    @State private var check = Check.idle
    @State private var choosingModel = false

    enum Check: Equatable { case idle, checking, connected(Int), failed(String) }

    private var hasKey: Bool { settings.aiKeysSaved.contains(provider) }

    var body: some View {
        Section {
            if provider == .localServer {
                TextField("Server Address", text: Binding(get: { settings.aiServerAddress },
                                                          set: { settings.aiServerAddress = $0; check = .idle }),
                          prompt: Text(AIProvider.defaultLocalServer))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }
            if hasKey {
                LabeledContent("API Key", value: "Saved")
                Button("Remove API Key", role: .destructive) {
                    settings.setAIKey("", for: provider)
                    check = .idle
                }
            } else {
                HStack {
                    SecureField("API Key", text: $keyDraft,
                                prompt: Text(provider.needsKey ? "Paste your key" : "Optional"))
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let page = provider.keysPage {
                    Button("Get an API Key") { openURL(page) }
                }
            }
            HStack {
                TextField("Model", text: Binding(get: { settings.aiModel(for: provider) },
                                                 set: { settings.setAIModel($0, for: provider) }),
                          prompt: Text(provider == .localServer ? "e.g. llama3.2" : provider.defaultModel))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button("Choose…") { choosingModel = true }
                    .disabled(models.isEmpty)
            }
            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    Text("Test Connection")
                    Spacer()
                    switch check {
                    case .idle, .failed: EmptyView()
                    case .checking: ProgressView().controlSize(.small)
                    case .connected(let count):
                        Label("\(count) models", symbol: .checkCircle).foregroundStyle(.green)
                    }
                }
            }
            .disabled(check == .checking || (provider.needsKey && !hasKey))
        } header: {
            Text(provider.name)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if case .failed(let message) = check {
                    Label(message, symbol: .warning).foregroundStyle(.orange)
                }
                FooterText(footer)
            }
        }
        .sheet(isPresented: $choosingModel) {
            ModelPicker(models: models, selection: Binding(get: { settings.aiModel(for: provider) },
                                                           set: { settings.setAIModel($0, for: provider) }))
        }
        .onChange(of: provider) {
            keyDraft = ""
            models = []
            check = .idle
        }
    }

    private var footer: String {
        let key = provider.needsKey ? " Your API key is kept in the Keychain on this device; it isn't synced or sent anywhere but \(provider.recipient)." : ""
        let test = " Test Connection asks \(provider.recipient) for its models; it sends no code."
        return provider.consentMessage + key + test
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        settings.setAIKey(key, for: provider)
        keyDraft = ""
        Task { await testConnection() }
    }

    private func testConnection() async {
        // Build the client even without a model, to list them.
        let client = RemoteAIClient(provider: provider, model: settings.aiModel(for: provider),
                                    serverAddress: settings.aiServerAddress, keys: settings.aiKeys)
        check = .checking
        do {
            models = try await client.models()
            check = .connected(models.count)
        } catch {
            models = []
            check = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// The provider's models, searchable (OpenRouter lists hundreds).
private struct ModelPicker: View {
    let models: [String]
    @Binding var selection: String
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var shown: [String] {
        search.isEmpty ? models : models.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(shown, id: \.self) { model in
                Button {
                    selection = model
                    dismiss()
                } label: {
                    HStack {
                        Text(model).foregroundStyle(.primary)
                        Spacer()
                        if model == selection { Icon(.check).foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Search models")
            .navigationTitle("Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}
