import ByteCacheCore
import SwiftUI

/// Edit a saved server: its display name and address. A new address is checked before saving.
struct ServerEditView: View {
    let session: SessionManager
    let account: Credentials
    @State private var name: String
    @State private var address: String
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(session: SessionManager, account: Credentials) {
        self.session = session
        self.account = account
        _name = State(initialValue: account.name ?? "")
        _address = State(initialValue: account.server.base.absoluteString)
    }

    private var isActive: Bool { account.id == session.activeAccountID }

    var body: some View {
        SettingsList {
            Section {
                TextField("Name", text: $name, prompt: Text(account.address))
            } footer: {
                Text("Optional. Shown instead of the address in Servers and the sidebar.")
            }
            Section {
                TextField("Server address", text: $address)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Address")
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Use this when your server moves to a new address. ByteCache checks the new address and keeps your login.")
                }
            }
            Section("Login") {
                LabeledContent("Signed in as", value: account.loginDescription)
                if isActive && account.isSignedIn {
                    Button("Sign Out", role: .destructive) {
                        session.signOut()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Edit Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .disabled(isSaving)
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await session.updateServer(account.id, name: name, address: address)
            dismiss()
        } catch {
            self.error = ErrorText.message(for: error)
        }
    }
}
