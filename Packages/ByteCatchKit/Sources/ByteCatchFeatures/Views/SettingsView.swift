import ByteCatchCore
import SwiftUI

/// Settings in the style of the iOS Settings app: grouped rows with coloured icons.
public struct SettingsView: View {
    let session: SessionManager
    @Environment(AppSettings.self) private var settings

    public init(session: SessionManager) {
        self.session = session
    }

    public var body: some View {
        List {
            if case .signedIn(let server, let user) = session.state {
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if user.username == SessionManager.apiKeyUserName {
                                Image(systemName: "key.fill")
                            } else {
                                Text(String(user.username.prefix(1)).uppercased())
                            }
                        }
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(settings.accent.color.gradient, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.username.isEmpty ? "Signed In" : user.username).font(.title3.weight(.semibold))
                                .accessibilityLabel(user.username == SessionManager.apiKeyUserName ? "Signed in with an API key" : user.username)
                            Text(server.base.host() ?? server.base.absoluteString)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsLabel(title: "Appearance", systemName: "circle.lefthalf.filled", color: .blue,
                                  value: settings.appearance.title)
                }
                NavigationLink {
                    CodeThemeSettingsView()
                } label: {
                    SettingsLabel(title: "Code Theme", systemName: "chevron.left.forwardslash.chevron.right",
                                  color: .purple, value: settings.codeTheme.name)
                }
            }

            Section {
                NavigationLink {
                    SyncSettingsView()
                } label: {
                    SettingsLabel(title: "iCloud & Handoff", systemName: "icloud.fill", color: .cyan,
                                  value: settings.iCloudSyncEnabled || settings.handoffEnabled ? "On" : "Off")
                }
            }

            Section {
                NavigationLink {
                    ServersView(session: session)
                } label: {
                    SettingsLabel(title: "Servers", systemName: "server.rack", color: .green,
                                  value: session.accounts.count > 1 ? "\(session.accounts.count)" : session.accounts.first?.displayName)
                }
            }

            if case .signedIn = session.state {
                Section {
                    Button("Sign Out", role: .destructive) {
                        SpotlightIndexer.removeAll()
                        session.signOut()
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Section {
                NavigationLink {
                    PrivacyInfoView()
                } label: {
                    SettingsLabel(title: "Privacy", systemName: "hand.raised.fill", color: .blue)
                }
                NavigationLink {
                    AboutView()
                } label: {
                    SettingsLabel(title: "About", systemName: "info", color: .gray, value: AboutText.version)
                }
            } footer: {
                Text("\(AboutText.appName) — \(AboutText.tagline)")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Settings")
    }
}

struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            Section("Appearance") {
                HStack(spacing: 0) {
                    ForEach(AppAppearance.allCases) { option in
                        Button { settings.appearance = option } label: {
                            VStack(spacing: 8) {
                                AppearancePreview(option: option)
                                Text(option.title).font(.subheadline)
                                Image(systemName: settings.appearance == option ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(settings.appearance == option ? settings.accent.color : .secondary)
                                    .font(.title3)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(settings.appearance == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 8)
            }
            Section("Accent Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button { settings.accent = choice } label: {
                            Circle()
                                .fill(choice.color.gradient)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if settings.accent == choice {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(settings.accent == choice ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Appearance")
    }
}

/// A tiny phone mock-up in light, dark, or split for Automatic.
private struct AppearancePreview: View {
    let option: AppAppearance

    var body: some View {
        ZStack {
            switch option {
            case .light: screen(dark: false)
            case .dark: screen(dark: true)
            case .system:
                screen(dark: false)
                    .overlay(alignment: .trailing) { screen(dark: true).mask(Rectangle().frame(width: 26).frame(maxWidth: .infinity, alignment: .trailing)) }
            }
        }
        .frame(width: 52, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
    }

    private func screen(dark: Bool) -> some View {
        let bg: Color = dark ? .black : .white, line: Color = dark ? .white.opacity(0.35) : .black.opacity(0.18)
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<5) { i in Capsule().fill(line).frame(width: [30, 22, 34, 18, 26][i], height: 4) }
        }
        .padding(8)
        .frame(width: 52, height: 92, alignment: .topLeading)
        .background(bg)
    }
}

struct CodeThemeSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    private static let sample = """
    // Fetch and decode a user
    func loadUser(id: Int) async throws -> User {
        let url = URL(string: "https://api.example.com/users/\\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(User.self, from: data)
    }
    """

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                CodeView(code: Self.sample, language: "swift")
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } header: {
                Text("Preview")
            }

            Section("Text") {
                HStack {
                    Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                    Slider(value: $settings.codeFontSize, in: AppSettings.fontSizes, step: 1)
                    Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                }
                LabeledContent("Font Size", value: "\(Int(settings.codeFontSize)) pt")
                Toggle("Line Numbers", isOn: $settings.showLineNumbers)
            }

            themeSection("Follows Appearance", .adaptive)
            themeSection("Dark", .dark)
            themeSection("Light", .light)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Code Theme")
    }

    private func themeSection(_ title: String, _ style: CodeTheme.Style) -> some View {
        Section(title) {
            ForEach(CodeTheme.all.filter { $0.style == style }) { theme in
                Button { settings.codeThemeID = theme.id } label: {
                    HStack(spacing: 12) {
                        ThemeSwatch(palette: theme.palette(for: colorScheme))
                        Text(theme.name).foregroundStyle(.primary)
                        Spacer()
                        if settings.codeThemeID == theme.id {
                            Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                        }
                    }
                }
                .accessibilityAddTraits(settings.codeThemeID == theme.id ? .isSelected : [])
            }
        }
    }
}

struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section {
                Label("No analytics, tracking or ads.", systemImage: "eye.slash")
                Label("Snippets go only to the server you enter.", systemImage: "server.rack")
                Label("Your login is kept in the Keychain; your password is never stored.", systemImage: "key")
                Label("Copied text is read only when you tap Paste.", systemImage: "doc.on.clipboard")
                Label("Language detection runs on this device.", systemImage: "cpu")
            } footer: {
                Text(AboutText.privacy)
            }
        }
        .navigationTitle("Privacy")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: AboutText.version)
                Text(AboutText.tagline)
                Text("ByteCatch is not affiliated with the ByteStash project.").foregroundStyle(.secondary)
            }
            Section("Acknowledgements") {
                Text("HighlightSwift — MIT License, © 2023 Stefan Britton")
                Text("highlight.js — BSD 3-Clause License, © 2006 Ivan Sagalaev")
                Text("Dracula, Monokai, Nord, Gruvbox, Night Owl and Catppuccin colour palettes by their respective authors (MIT).")
                Text("Language model trained on permissively licensed open-source code.").foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
        .navigationTitle("About")
    }
}

struct SyncSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CloudSyncCoordinator.self) private var sync

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Toggle(isOn: $settings.iCloudSyncEnabled) {
                    SettingsLabel(title: "iCloud Sync", systemName: "icloud.fill", color: .cyan)
                }
                .onChange(of: settings.iCloudSyncEnabled) {
                    if settings.iCloudSyncEnabled { Task { await sync.syncNow() } }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keeps your appearance, code theme and server list the same on your iPhone, iPad and Mac. Logins and API keys stay on each device — sign in once on each one.")
                    if !UbiquitousSyncStore.isAvailable {
                        Label("This device isn't signed in to iCloud.", systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Toggle(isOn: $settings.handoffEnabled) {
                    SettingsLabel(title: "Handoff", systemName: "macbook.and.iphone", color: .blue)
                }
            } footer: {
                Text("Pick up the snippet you're viewing on another device signed in to the same Apple Account. Devices without ByteCatch open it in the ByteStash web app.")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("iCloud & Handoff")
    }
}
