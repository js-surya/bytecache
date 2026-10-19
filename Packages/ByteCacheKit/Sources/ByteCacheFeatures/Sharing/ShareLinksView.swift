import ByteCacheCore
import SwiftUI

/// Create, copy, QR and revoke share links for a snippet.
struct ShareLinksView: View {
    @State var model: ShareLinksModel
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var copiedID: String?

    var body: some View {
        Form {
            if !model.canManage {
                ContentUnavailableView("Password Sign-In Needed", symbol: .keyOff,
                                       description: Text("ByteStash only lets you create share links when you're signed in with a password."))
            } else {
                if let url = model.newestURL {
                    Section {
                        if let qr = QRCode.cgImage(for: url.absoluteString) {
                            Image(decorative: qr, scale: 1)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .accessibilityLabel("QR code for the share link")
                        }
                        Text(url.absoluteString).font(.callout.monospaced()).textSelection(.enabled)
                        HStack {
                            Button { copy(url, id: "new") } label: {
                                Label(copiedID == "new" ? "Copied" : "Copy Link", symbol: copiedID == "new" ? .check : .copy)
                            }
                            Spacer()
                            SwiftUI.ShareLink(item: url) { Label("Share", symbol: .share) }
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        Text("New Link")
                    }
                }

                Section {
                    Picker("Expires", selection: $model.expiry) {
                        ForEach(ShareExpiry.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Require Sign-In to View", isOn: $model.requiresAuth)
                    Button {
                        Task { await model.create() }
                    } label: {
                        HStack {
                            Label("Create Share Link", symbol: .link)
                            if model.isWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(model.isWorking)
                } header: {
                    Text("Create")
                } footer: {
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                    else { Text("Anyone with the link can view “\(title)” until it expires or you revoke it.") }
                }

                if !model.links.isEmpty {
                    Section("Active Links") {
                        ForEach(model.links) { link in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(link.id.prefix(10) + "…").font(.callout.monospaced())
                                    Text(status(link)).font(.caption).foregroundStyle(link.expired ? .red : .secondary)
                                }
                                Spacer()
                                if let url = model.url(for: link) {
                                    Button { copy(url, id: link.id) } label: {
                                        Label(copiedID == link.id ? "Copied" : "Copy", symbol: copiedID == link.id ? .check : .copy)
                                            .labelStyle(.iconOnly)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Button(role: .destructive) { Task { await model.revoke(link) } } label: {
                                    Label("Revoke", symbol: .trash).labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Share Link")
        .toolbar { Button("Done") { dismiss() } }
        .task { await model.load() }
    }

    private func status(_ link: ByteCacheCore.ShareLink) -> String {
        var parts: [String] = []
        if link.expired {
            parts.append("Expired")
        } else if let expires = link.expiresAt {
            parts.append("Expires \(expires.formatted(.relative(presentation: .named)))")
        } else {
            parts.append("Never expires")
        }
        if link.requiresAuth { parts.append("sign-in required") }
        return parts.joined(separator: " · ")
    }

    private func copy(_ url: URL, id: String) {
        Pasteboard.copy(url.absoluteString)
        copiedID = id
    }
}
