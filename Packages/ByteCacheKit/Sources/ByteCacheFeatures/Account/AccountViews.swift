import ByteCacheCore
import SwiftUI

struct APIKeysView: View {
    @State var model: AccountModel
    @State private var newName = ""
    @State private var copied = false

    var body: some View {
        SettingsList {
            if !model.canManage {
                ContentUnavailableView("Password Sign-In Needed", symbol: .keyOff,
                                       description: Text("ByteStash only lets you manage API keys when you're signed in with a password."))
            } else {
                if let created = model.newKey {
                    Section {
                        Text(created.key)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            Pasteboard.copy(created.key, toast: false)
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy Key", symbol: copied ? .check : .copy)
                        }
                        Button("Done") {
                            model.dismissNewKey()
                            copied = false
                        }
                    } header: {
                        Text("New key “\(created.info.name)”")
                    } footer: {
                        Text("Copy it now — ByteStash won't show this key again, and ByteCache doesn't keep it.")
                    }
                }

                Section {
                    HStack {
                        TextField("Key name, e.g. Work laptop", text: $newName)
                            .onSubmit(create)
                        Button("Create", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("New Key")
                } footer: {
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                }

                Section {
                    if model.keys.isEmpty && !model.isLoading {
                        Text("No API keys yet.").foregroundStyle(.secondary)
                    }
                    ForEach(model.keys) { key in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(key.name)
                            HStack(spacing: 4) {
                                if let created = key.createdAt {
                                    Text("Created \(created.formatted(date: .abbreviated, time: .omitted))")
                                }
                                Text("·")
                                if let used = key.lastUsedAt {
                                    Text("Used \(used.formatted(.relative(presentation: .named)))")
                                } else {
                                    Text("Never used")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button(role: .destructive) { Task { await model.deleteKey(key) } } label: {
                                Label("Delete Key", symbol: .trash)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { model.keys[$0] }
                        Task { for key in doomed { await model.deleteKey(key) } }
                    }
                } header: {
                    Text("Your Keys")
                } footer: {
                    Text("Deleting a key signs out anything using it, including ByteCache on other devices.")
                }
            }
        }
        .navigationTitle("API Keys")
        .refreshable { await model.loadKeys() }
        .task { await model.loadKeys() }
    }

    private func create() {
        let name = newName
        Task {
            await model.createKey(name: name)
            if model.newKey != nil { newName = "" }
        }
    }
}

struct ChangePasswordView: View {
    @State var model: AccountModel
    @State private var working = false

    var body: some View {
        SettingsList {
            if !model.canManage {
                ContentUnavailableView("Password Sign-In Needed", symbol: .keyOff,
                                       description: Text("You're signed in with an API key. Sign in with your password to change it."))
            } else if !model.allowPasswordChanges {
                ContentUnavailableView("Turned Off on This Server", symbol: .lockOpen,
                                       description: Text("The ByteStash administrator has disabled password changes."))
            } else {
                Section {
                    SecureField("Current password", text: $model.currentPassword)
                        .textContentType(.password)
                }
                Section {
                    SecureField("New password", text: $model.newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm new password", text: $model.confirmPassword)
                        .textContentType(.newPassword)
                } footer: {
                    if let problem = model.passwordProblem {
                        Text(problem).foregroundStyle(.red)
                    } else if let error = model.error {
                        Text(error).foregroundStyle(.red)
                    } else if model.passwordChanged {
                        Label("Password changed.", symbol: .checkCircle).foregroundStyle(.green)
                    }
                }
                Section {
                    Button {
                        working = true
                        Task {
                            await model.changePassword()
                            working = false
                        }
                    } label: {
                        ZStack {
                            Text("Change Password").opacity(working ? 0 : 1)
                            if working { ProgressView() }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canChangePassword || working)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Change Password")
        .task { await model.loadKeys() }
    }
}
