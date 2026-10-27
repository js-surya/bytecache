import ByteCacheCore
import SwiftUI

/// Settings → AI Assistants (MCP): connect Claude, ChatGPT and other assistants to your ByteStash snippets.
struct MCPSettingsView: View {
    @Bindable var model: MCPSettingsModel
    @State private var pastedKey = ""

    var body: some View {
        SettingsList {
            Section {
                if let endpoint = model.endpoint {
                    HStack {
                        Text(endpoint.absoluteString).font(.callout.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button { Pasteboard.copy(endpoint.absoluteString) } label: { Label("Copy", symbol: .copy) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Copy endpoint")
                    }
                }
                if model.isPrivateServer {
                    Label {
                        Text("This server is on a private network, so it works with assistants on your own devices (Claude Code, Claude Desktop, Cursor, VS Code). Web assistants like Claude.ai, ChatGPT and Perplexity connect from their company's servers and can't reach it unless you make ByteStash reachable from the internet, for example with Tailscale Funnel.")
                    } icon: {
                        Icon(.infoCircle)
                    }
                    .labelStyle(NoticeLabelStyle())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if !model.isHTTPS {
                    Label("Assistants outside your network need an HTTPS address. Put ByteStash behind HTTPS to use them.",
                          symbol: .warning)
                        .labelStyle(NoticeLabelStyle())
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Your MCP endpoint")
            } footer: {
                InfoFooter("Your ByteStash server has an MCP endpoint. AI assistants use it to search, read, create and edit your snippets with an API key. They talk to your server directly, not through ByteCache.")
            }

            Section {
                if let hint = model.savedKeyHint {
                    LabeledContent("Saved key", value: hint)
                    Toggle("Put the key in the setup below", isOn: $model.insertKey)
                    Button { Task { await model.testConnection() } } label: { Label("Test Connection", symbol: .refresh) }
                    Button(role: .destructive) { model.forgetKey() } label: { Label("Forget Key on This Device", symbol: .trash) }
                } else {
                    if model.canCreateKey {
                        Button { Task { await model.createKey() } } label: { Label("Create a Key for Assistants", symbol: .key) }
                    }
                    if let loginKey = model.loginKey {
                        Button { Task { await model.useKey(loginKey) } } label: { Label("Use the Key I Signed In With", symbol: .key) }
                    }
                    SecureField("Or paste a key from ByteStash", text: $pastedKey)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit { Task { await model.useKey(pastedKey); pastedKey = "" } }
                    if !pastedKey.isEmpty {
                        Button("Use This Key") { Task { await model.useKey(pastedKey); pastedKey = "" } }
                    }
                }
                if model.isWorking {
                    HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
                } else if let status = model.status {
                    StatusRow(status: status)
                }
            } header: {
                Text("API key")
            } footer: {
                FooterText("The key is kept in this device's Keychain and never shown in full again. To revoke it, delete it in Settings → API Keys. Anyone with the key can read and change your snippets.")
            }

            Section {
                ForEach(model.clients) { client in
                    DisclosureGroup {
                        Text(client.how).font(.footnote).foregroundStyle(.secondary)
                        Text(client.text)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        HStack {
                            Button { model.copy(client) } label: { Label("Copy", symbol: .copy) }
                            Spacer()
                            ShareLink(item: client.text) { Label("Send to Computer", symbol: .share) }
                        }
                        .buttonStyle(.borderless)
                    } label: {
                        HStack {
                            Text(client.name)
                            if client.runsInCloud && model.isPrivateServer {
                                Spacer()
                                Text("Needs a public address").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("Set up an assistant")
            } footer: {
                FooterText(model.insertKey ? "The setup includes your key; share it only with your own devices."
                                     : "Replace YOUR_API_KEY with your key, or turn on “Put the key in the setup below”.")
            }
        }
        .navigationTitle("AI Assistants (MCP)")
        .task { if model.savedKeyHint != nil, model.status == nil { await model.testConnection() } }
        .alert("Something went wrong", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }
}

/// Icon aligned with the first line of a multi-line notice (the default label centres it on Mac).
private struct NoticeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StatusRow: View {
    let status: MCPStatus

    var body: some View {
        switch status {
        case .ready(let tools):
            Label("Connected · \(tools.count) tools", symbol: .checkCircle).foregroundStyle(.green)
        case .badKey:
            Label("The server didn't accept this key.", symbol: .warning).foregroundStyle(.red)
        case .notSupported:
            Label("This server has no MCP endpoint. Update ByteStash to use AI assistants.", symbol: .warning).foregroundStyle(.orange)
        case .offline:
            Label("Couldn't reach the server.", symbol: .offline).foregroundStyle(.orange)
        case .failed(let message):
            Label(message, symbol: .warning).foregroundStyle(.red)
        }
    }
}
