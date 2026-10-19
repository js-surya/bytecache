import ByteCacheCore
import SwiftUI

extension Credentials {
    /// Host (and sub-path) for lists.
    public var displayName: String {
        name ?? address
    }

    /// Host (and sub-path), ignoring any custom name.
    public var address: String {
        let host = server.base.host() ?? server.base.absoluteString
        let path = server.base.path
        return path.isEmpty || path == "/" ? host : host + path
    }

    public var loginDescription: String {
        if apiKey != nil { return SessionManager.apiKeyUserName }
        if token != nil { return username ?? "Signed in" }
        return "Not signed in"
    }
}

/// Saved servers: switch, edit, add, remove.
struct ServersView: View {
    let session: SessionManager
    @State private var editing: Credentials?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(session.accounts) { account in
                    Button {
                        Task { await session.switchTo(account.id) }
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(account.apiKey != nil ? .key : .server,
                                         color: account.isSignedIn ? .green : .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName).foregroundStyle(.primary)
                                Text(account.loginDescription).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if account.id == session.activeAccountID {
                                Icon(.check).foregroundStyle(.tint).fontWeight(.semibold)
                            }
                            Button { editing = account } label: { Icon(.info) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Edit \(account.displayName)")
                        }
                    }
                    .tint(.primary)
                    .accessibilityAddTraits(account.id == session.activeAccountID ? .isSelected : [])
                    .swipeActions(edge: .leading) {
                        Button { editing = account } label: { Label("Edit", symbol: .edit) }
                            .tint(.blue)
                    }
                    .contextMenu {
                        Button { editing = account } label: { Label("Edit Server…", symbol: .edit) }
                        Button(role: .destructive) { Task { await session.removeAccount(account.id) } } label: {
                            Label("Remove Server", symbol: .trash)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { session.accounts[$0].id }
                    Task { for id in ids { await session.removeAccount(id) } }
                }
            } footer: {
                Text("Tap ⓘ to rename a server or change its address. Swipe or right-click a server to remove it. Removing a server forgets its login on this device; nothing is deleted on the server.")
            }
            Section {
                Button {
                    SpotlightIndexer.removeAll()
                    session.addServer()
                    dismiss()
                } label: {
                    Label("Add Server", symbol: .plusCircle)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Servers")
        .sheet(item: $editing) { account in
            NavigationStack { ServerEditView(session: session, account: account) }
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 380)
                #endif
        }
    }
}

/// Compact switcher for the sidebar toolbar.
public struct ServerMenu: View {
    let session: SessionManager

    public init(session: SessionManager) {
        self.session = session
    }

    public var body: some View {
        Menu {
            ForEach(session.accounts) { account in
                Button {
                    SpotlightIndexer.removeAll()
                    Task { await session.switchTo(account.id) }
                } label: {
                    if account.id == session.activeAccountID {
                        Label(account.displayName, symbol: .check)
                    } else {
                        Text(account.displayName)
                    }
                }
            }
            Divider()
            Button {
                SpotlightIndexer.removeAll()
                session.addServer()
            } label: {
                Label("Add Server…", symbol: .plus)
            }
        } label: {
            Label("Servers", symbol: .server)
        }
    }
}
