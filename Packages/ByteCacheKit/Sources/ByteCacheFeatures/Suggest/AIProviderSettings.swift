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
    @State private var search = ""

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
            if models.isEmpty {
                // Before the list loads (or if the server can't list them): type the model's name.
                TextField("Model", text: Binding(get: { settings.aiModel(for: provider) },
                                                 set: { settings.setAIModel($0, for: provider) }),
                          prompt: Text(provider == .localServer ? "e.g. llama3.2" : provider.defaultModel))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } else {
                modelList
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
                InfoFooter(footer)
            }
        }
        .onChange(of: provider) {
            keyDraft = ""
            search = ""
            models = []
            check = .idle
        }
        // Fill the model list as soon as there's a key (or a local server) to ask.
        .task(id: provider) {
            if models.isEmpty, check == .idle, hasKey || !provider.needsKey { await testConnection() }
        }
    }

    /// The current model, a search field and a few matching models from the provider's list.
    @ViewBuilder private var modelList: some View {
        let selection = settings.aiModel(for: provider)
        let choices = ModelChoices(models: models, suggested: provider.suggestedModels,
                                   selection: selection, search: search)
        LabeledContent("Model", value: selection.isEmpty ? "None" : selection)
        HStack {
            Icon(.search).foregroundStyle(.secondary)
            TextField("Search Models", text: $search, prompt: Text("Search \(models.count) models"))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
        if choices.shown.isEmpty {
            Text("No models match “\(search)”.").font(.caption).foregroundStyle(.secondary)
        } else {
            // Its own scroll area, so hundreds of models (OpenRouter) don't make Settings endless.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(choices.shown) { model in
                        Button {
                            settings.setAIModel(model.id, for: provider)
                            search = ""
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.id).foregroundStyle(.primary)
                                    if !model.detail.isEmpty {
                                        Text(model.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if model.id == selection { Icon(.check).foregroundStyle(.tint) }
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if model.id != choices.shown.last?.id { Divider() }
                    }
                }
            }
            .frame(height: min(CGFloat(choices.shown.count) * 44, 264))
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var footer: String {
        provider.needsKey
            ? "Your key stays in this device's Keychain and goes only to \(provider.name). Test Connection sends no code."
            : "Test Connection sends no code."
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

/// The models in the scrolling list: with no search, the suggested ones the provider has and the current
/// choice first, then the rest; with a search, only the matches.
struct ModelChoices {
    let shown: [SuggestedModel]

    init(models: [String], suggested: [SuggestedModel], selection: String, search: String) {
        let query = search.trimmingCharacters(in: .whitespaces)
        let available = Set(models)
        let detail = Dictionary(suggested.map { ($0.id, $0.detail) }, uniquingKeysWith: { first, _ in first })
        let ordered: [String] = if query.isEmpty {
            suggested.map(\.id).filter(available.contains)
                + (available.contains(selection) ? [selection] : [])
                + models
        } else {
            models.filter { $0.localizedCaseInsensitiveContains(query) }
        }
        var seen = Set<String>()
        shown = ordered.filter { seen.insert($0).inserted }.map { SuggestedModel(id: $0, detail: detail[$0] ?? "") }
    }
}
